import Foundation
import SwiftUSB

private let gipInputEndpointAddress: UInt8 = 0x82
private let gipReadPacketLength = 64
private let gipReadTimeoutMs: UInt32 = 100
private let pipelineErrorRecoveryDelay: UInt64 = 10_000_000
private let usbOpenRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]

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
    do {
      let events = try parser.parse(data: data)
      if !events.isEmpty { await dispatcher.dispatch(events: events, from: identifier) }
    } catch { print("[DevicePipeline] Parse error" + " for \(identifier): \(error)") }
  }

  // MARK: - Private USB pipeline

  private func startUSBPipeline(vendorID: UInt16, productID: UInt16) async {
    let context: USBContext
    do { context = try USBContext() } catch {
      print("[DevicePipeline] Failed to create USBContext" + " for \(identifier): \(error)")
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

    do {
      try await parser.performHandshake(handle: handle)
      print("[DevicePipeline] Handshake complete:" + " \(identifier)")
    } catch {
      print("[DevicePipeline] Handshake failed" + " for \(identifier): \(error)")
      try? handle.releaseInterface(0)
      usbHandle = nil
      isActive = false
      return
    }

    await runUSBInputLoop(handle: handle)
  }

  private func openDeviceWithRetry(context: USBContext, vendorID: UInt16, productID: UInt16) async
    -> USBDeviceHandle?
  {
    for attempt in 0..<usbOpenRetryDelays.count {
      do {
        guard let device = await context.findDevice(vendorId: vendorID, productId: productID) else {
          print(
            "[DevicePipeline] Device not found" + " (attempt \(attempt + 1)):" + " \(identifier)"
          )
          try await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
          continue
        }
        let handle = try device.open()
        try handle.claimInterface(0)
        return handle
      } catch {
        print(
          "[DevicePipeline] Open attempt" + " \(attempt + 1) failed"
            + " for \(identifier): \(error)"
        )
        if attempt < usbOpenRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
        }
      }
    }
    return nil
  }

  private func runUSBInputLoop(handle: USBDeviceHandle) async {
    let inEndpoint = gipInputEndpointAddress
    print("[DevicePipeline] Starting USB input loop:" + " \(identifier)")

    while isActive {
      do {
        let bytes = try handle.readInterrupt(
          endpoint: inEndpoint,
          length: gipReadPacketLength,
          timeout: gipReadTimeoutMs
        )
        let events = try parser.parse(data: Data(bytes))
        if !events.isEmpty { await dispatcher.dispatch(events: events, from: identifier) }
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
}
