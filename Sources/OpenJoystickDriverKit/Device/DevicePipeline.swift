import Foundation
import SwiftUSB

private let gipInputEndpointAddress: UInt8 = 0x82
private let gipReadPacketLength = 64
private let gipReadTimeoutMs: UInt32 = 100
private let pipelineErrorRecoveryDelay: UInt64 = 10_000_000
private let usbOpenRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
/// Send keep-alive every 40 read cycles × 100 ms timeout ≈ 4 seconds.
private let keepAliveCycleInterval: UInt = 40

/// Manages full lifecycle of single connected controller.
/// Each controller gets its own DevicePipeline actor - one
/// failure never affects others.
actor DevicePipeline {
  enum Transport {
    /// Class 0xFF via SwiftUSB
    case usb(vendorID: UInt16, productID: UInt16)
    /// Class 0x03 via IOKit
    case hid(locationID: UInt32)
  }

  let identifier: DeviceIdentifier
  private let transport: Transport
  private let parser: any InputParser
  private let dispatcher: any OutputDispatcher
  private var isActive = false
  private var usbHandle: USBDeviceHandle?
  private var currentInputState: DeviceInputState
  private var packetLog: [PacketLogEntry] = []
  private let maxPacketLogEntries = 200

  init(
    identifier: DeviceIdentifier,
    transport: Transport,
    parser: any InputParser,
    dispatcher: any OutputDispatcher
  ) {
    self.identifier = identifier
    self.transport = transport
    self.parser = parser
    self.dispatcher = dispatcher
    self.currentInputState = DeviceInputState(
      vendorID: identifier.vendorID,
      productID: identifier.productID
    )
  }

  /// Start pipeline: open device, handshake, begin input loop.
  func start() async {
    guard !isActive else { return }
    isActive = true

    switch transport {
    case .usb(let vid, let pid): await startUSBPipeline(vendorID: vid, productID: pid)
    case .hid:
      // HID pipeline: data fed via feedHIDData(); no separate startup loop needed
      print("[DevicePipeline] HID pipeline ready" + " for \(identifier)")
    }
  }

  /// Stop pipeline and clean up resources.
  func stop() {
    isActive = false
    if let handle = usbHandle {
      try? handle.releaseInterface(0)
      usbHandle = nil
    }
    print("[DevicePipeline] Stopped: \(identifier)")
  }

  /// Feed HID input report data (called by DeviceManager for class 0x03 devices).
  func feedHIDData(_ data: Data) async {
    guard isActive else { return }
    appendToPacketLog(bytes: Array(data), direction: "rx")
    do {
      let events = try parser.parse(data: data)
      if !events.isEmpty { await dispatcher.dispatch(events: events, from: identifier) }
      updateInputState(from: events)
    } catch { print("[DevicePipeline] Parse error" + " for \(identifier): \(error)") }
  }

  // MARK: - Input state and packet log

  func inputState() -> DeviceInputState { currentInputState }
  func getPacketLog() -> [PacketLogEntry] { packetLog }

  private func updateInputState(from events: [ControllerEvent]) {
    for event in events {
      switch event {
      case .buttonPressed(let button):
        let raw = button.rawValue
        if !currentInputState.pressedButtons.contains(raw) {
          currentInputState.pressedButtons.append(raw)
        }
      case .buttonReleased(let button):
        currentInputState.pressedButtons.removeAll { $0 == button.rawValue }
      case .leftStickChanged(let x, let y):
        currentInputState.leftStickX = x
        currentInputState.leftStickY = y
      case .rightStickChanged(let x, let y):
        currentInputState.rightStickX = x
        currentInputState.rightStickY = y
      case .leftTriggerChanged(let v): currentInputState.leftTrigger = v
      case .rightTriggerChanged(let v): currentInputState.rightTrigger = v
      case .dpadChanged: break
      }
    }
  }

  private func appendToPacketLog(bytes: [UInt8], direction: String) {
    let hexString = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    let entry = PacketLogEntry(
      timestamp: Date().timeIntervalSince1970,
      direction: direction,
      hex: hexString,
      length: bytes.count
    )
    packetLog.append(entry)
    if packetLog.count > maxPacketLogEntries {
      packetLog.removeFirst(packetLog.count - maxPacketLogEntries)
    }
  }

  // MARK: - Rumble

  func sendRumble(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) {
    guard let handle = usbHandle else { return }
    guard let gipParser = parser as? GIPParser else { return }
    do {
      try gipParser.sendRumble(handle: handle, left: left, right: right, ltMotor: lt, rtMotor: rt)
    } catch { print("[DevicePipeline] Rumble send failed for \(identifier): \(error)") }
  }

  // MARK: - Private USB pipeline

  private func startUSBPipeline(vendorID: UInt16, productID: UInt16) async {
    guard let context = createUSBContext() else {
      isActive = false
      return
    }

    guard
      let handle = await openDeviceWithRetry(
        context: context,
        vendorID: vendorID,
        productID: productID
      )
    else {
      print("[DevicePipeline] Could not open USB device" + " \(identifier) after retries")
      isActive = false
      return
    }
    usbHandle = handle

    guard await performUSBHandshake(handle: handle) else {
      isActive = false
      return
    }

    await runUSBInputLoop(handle: handle)
  }

  private func createUSBContext() -> USBContext? {
    do { return try USBContext() } catch {
      print("[DevicePipeline] Failed to create USBContext" + " for \(identifier): \(error)")
      return nil
    }
  }

  private func performUSBHandshake(handle: USBDeviceHandle) async -> Bool {
    do {
      try await parser.performHandshake(handle: handle)
      print("[DevicePipeline] Handshake complete:" + " \(identifier)")
      return true
    } catch {
      print("[DevicePipeline] Handshake failed" + " for \(identifier): \(error)")
      try? handle.releaseInterface(0)
      usbHandle = nil
      return false
    }
  }

  private func openDeviceWithRetry(context: USBContext, vendorID: UInt16, productID: UInt16) async
    -> USBDeviceHandle?
  {
    for attempt in 0..<usbOpenRetryDelays.count {
      do {
        guard
          let device = await findDevice(
            on: context,
            vendorID: vendorID,
            productID: productID,
            attempt: attempt
          )
        else {
          try await sleepForRetry(attempt: attempt)
          continue
        }
        return try openAndClaimDevice(device)
      } catch {
        handleOpenDeviceError(error, attempt: attempt)
        if attempt < usbOpenRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
        }
      }
    }
    return nil
  }

  private func findDevice(on context: USBContext, vendorID: UInt16, productID: UInt16, attempt: Int)
    async -> USBDevice?
  {
    guard let device = await context.findDevice(vendorId: vendorID, productId: productID) else {
      print("[DevicePipeline] Device not found (attempt \(attempt + 1)):" + " \(identifier)")
      return nil
    }
    return device
  }

  private func openAndClaimDevice(_ device: USBDevice) throws -> USBDeviceHandle {
    let handle = try device.open()
    try handle.claimInterface(0)
    return handle
  }

  private func handleOpenDeviceError(_ error: Error, attempt: Int) {
    print("[DevicePipeline] Open attempt \(attempt + 1) failed" + " for \(identifier): \(error)")
  }

  private func sleepForRetry(attempt: Int) async throws {
    try await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
  }

  private func runUSBInputLoop(handle: USBDeviceHandle) async {
    let inEndpoint = gipInputEndpointAddress
    var keepAliveCycle: UInt = 0
    print("[DevicePipeline] Starting USB input loop:" + " \(identifier)")

    while isActive {
      keepAliveCycle += 1
      if shouldSendKeepAlive(keepAliveCycle: keepAliveCycle) {
        keepAliveCycle = 0
        runKeepAlive(handle: handle)
      }
      do {
        let bytes = try readInterrupt(handle: handle, inEndpoint: inEndpoint)
        appendToPacketLog(bytes: bytes, direction: "rx")
        let events = try parseEvents(from: bytes)
        if !events.isEmpty { await dispatcher.dispatch(events: events, from: identifier) }
        updateInputState(from: events)
      } catch let error as USBError where error.isTimeout { continue } catch let error as USBError
        where error.isNoDevice
      {
        print("[DevicePipeline] Device disconnected:" + " \(identifier)")
        break
      } catch {
        print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error) - continuing")
        try? await Task.sleep(nanoseconds: pipelineErrorRecoveryDelay)
      }
    }

    try? handle.releaseInterface(0)
    usbHandle = nil
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
  }

  private func shouldSendKeepAlive(keepAliveCycle: UInt) -> Bool {
    keepAliveCycle >= keepAliveCycleInterval
  }

  private func runKeepAlive(handle: USBDeviceHandle) {
    do { try parser.keepAlive(handle: handle) } catch {
      print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)")
    }
  }

  private func readInterrupt(handle: USBDeviceHandle, inEndpoint: UInt8) throws -> [UInt8] {
    try handle.readInterrupt(
      endpoint: inEndpoint,
      length: gipReadPacketLength,
      timeout: gipReadTimeoutMs
    )
  }

  private func parseEvents(from bytes: [UInt8]) throws -> [ControllerEvent] {
    try parser.parse(data: Data(bytes))
  }
}
