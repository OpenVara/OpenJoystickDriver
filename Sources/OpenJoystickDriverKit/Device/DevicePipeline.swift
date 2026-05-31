import Foundation
import SwiftUSB

private let gipReadPacketLength = 64
private let gipReadTimeoutMs: UInt32 = 100
private let usbOpenRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
private let keepAliveIntervalNs: UInt64 = 4_000_000_000
/// Target input loop cadence in nanoseconds.
///
/// If libusb returns timeouts immediately (instead of waiting for timeout),
/// this prevents a hot loop that can trigger launchd "inefficient" kills.
private let usbIdleLoopCadenceNs: UInt64 = UInt64(gipReadTimeoutMs) * 1_000_000
private let usbIOErrorReconnectThreshold = 10
private let usbIOErrorBackoffBaseNs: UInt64 = 250_000_000  // 250ms
private let usbIOErrorBackoffMaxNs: UInt64 = 2_000_000_000  // 2s
private let usbIOErrorLogIntervalNs: UInt64 = 5_000_000_000  // 5s
private let defaultControllerIdleTimeoutNanoseconds: UInt64 = 30_000_000_000
private let defaultIdleMonitorIntervalNanoseconds: UInt64 = 1_000_000_000

private final class DevicePipelineSnapshots: @unchecked Sendable {
  private let lock = NSLock()
  private var inputState: DeviceInputState
  private var packetLog: [PacketLogEntry] = []
  private let maxPacketLogEntries: Int

  init(inputState: DeviceInputState, maxPacketLogEntries: Int) {
    self.inputState = inputState
    self.maxPacketLogEntries = maxPacketLogEntries
  }

  func updateInputState(_ state: DeviceInputState) {
    lock.withLock { inputState = state }
  }

  func currentInputState() -> DeviceInputState {
    lock.withLock { inputState }
  }

  func appendPacket(_ entry: PacketLogEntry) {
    lock.withLock {
      packetLog.append(entry)
      if packetLog.count > maxPacketLogEntries {
        packetLog.removeFirst(packetLog.count - maxPacketLogEntries)
      }
    }
  }

  func currentPacketLog() -> [PacketLogEntry] {
    lock.withLock { packetLog }
  }
}

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
  private let usbContext: USBContext?
  private let transportProfile: DeviceTransportProfile
  private let idleMonitorIntervalNanoseconds: UInt64
  private var isActive = false
  private var usbHandle: USBDeviceHandle?
  private var currentInputState: DeviceInputState
  private var outputState: DeviceInputState
  private var packetLog: [PacketLogEntry] = []
  private let maxPacketLogEntries = 200
  private let snapshots: DevicePipelineSnapshots
  private var sleepGate = ControllerSleepGate()
  private var idleMonitorTask: Task<Void, Never>?
  private var externalOutputAllowed: Bool
  private var waitingForExternalNeutral = false
  private var consecutiveUSBIOErrors: Int = 0
  private var lastUSBIOErrorLogNs: UInt64 = 0

  init(
    identifier: DeviceIdentifier,
    transport: Transport,
    parser: any InputParser,
    dispatcher: any OutputDispatcher,
    usbContext: USBContext?,
    transportProfile: DeviceTransportProfile = .gipDefault,
    externalOutputAllowed: Bool = true,
    idleTimeoutNanoseconds: UInt64 = defaultControllerIdleTimeoutNanoseconds,
    idleMonitorIntervalNanoseconds: UInt64 = defaultIdleMonitorIntervalNanoseconds
  ) {
    self.identifier = identifier
    self.transport = transport
    self.parser = parser
    self.dispatcher = dispatcher
    self.usbContext = usbContext
    self.transportProfile = transportProfile
    self.idleMonitorIntervalNanoseconds = idleMonitorIntervalNanoseconds
    self.externalOutputAllowed = externalOutputAllowed
    let initialState = DeviceInputState(
      vendorID: identifier.vendorID,
      productID: identifier.productID
    )
    self.currentInputState = initialState
    self.outputState = initialState
    self.snapshots = DevicePipelineSnapshots(
      inputState: initialState,
      maxPacketLogEntries: maxPacketLogEntries
    )
    self.sleepGate = ControllerSleepGate(idleTimeoutNanoseconds: idleTimeoutNanoseconds)
  }

  /// Start pipeline: open device, handshake, begin input loop.
  func start() async {
    guard !isActive else { return }
    isActive = true
    startIdleMonitor()

    switch transport {
    case .usb(let vid, let pid): await startUSBPipeline(vendorID: vid, productID: pid)
    case .hid:
      // HID pipeline: data fed via feedHIDData(); no separate startup loop needed
      print("[DevicePipeline] HID pipeline ready" + " for \(identifier)")
    }
  }

  /// Stop pipeline and clean up resources.
  func stop() async {
    isActive = false
    idleMonitorTask?.cancel()
    idleMonitorTask = nil
    await neutralizeOutput()
    if let listener = dispatcher as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
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
      await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
    } catch { print("[DevicePipeline] Parse error" + " for \(identifier): \(error)") }
  }

  nonisolated func supportsPhysicalRumble() -> Bool {
    if let usbOutput = parser as? PhysicalRumbleOutput {
      return usbOutput.supportsPhysicalRumble
    }
    if let hidOutput = parser as? PhysicalHIDRumbleOutput {
      return hidOutput.supportsPhysicalRumble
    }
    return false
  }

  // MARK: - Input state and packet log

  nonisolated func inputState() -> DeviceInputState { snapshots.currentInputState() }
  nonisolated func getPacketLog() -> [PacketLogEntry] { snapshots.currentPacketLog() }

  func setExternalOutputAllowed(_ allowed: Bool) async {
    let changed = externalOutputAllowed != allowed
    guard changed else { return }
    externalOutputAllowed = allowed

    if !allowed {
      waitingForExternalNeutral = false
      let neutralizingEvents = outputState.neutralizingEvents()
      if !neutralizingEvents.isEmpty {
        await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
        updateOutputState(from: neutralizingEvents)
      }
      print("[DevicePipeline] Output gated by foreground consumer: \(identifier)")
      return
    }

    let shouldWaitForNeutral = !currentInputState.isEffectivelyNeutral
    waitingForExternalNeutral = shouldWaitForNeutral

    if shouldWaitForNeutral {
      print(
        "[DevicePipeline] Foreground gate lifted; suppressing hidden "
          + "non-neutral state: \(identifier)"
      )
    } else {
      print(
        "[DevicePipeline] Output ungated by foreground consumer: \(identifier)"
      )
    }
  }

  private func updateObservedInputState(from events: [ControllerEvent]) {
    currentInputState.apply(events: events)
    snapshots.updateInputState(currentInputState)
  }

  private func updateOutputState(from events: [ControllerEvent]) {
    outputState.apply(events: events)
  }

  private func neutralizeOutput() async {
    let neutralizingEvents = outputState.neutralizingEvents()
    guard !neutralizingEvents.isEmpty else { return }
    await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
    updateOutputState(from: neutralizingEvents)
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
    snapshots.appendPacket(entry)
  }

  // MARK: - Rumble

  func sendRumble(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) -> Bool {
    guard let handle = usbHandle, let rumbleOutput = parser as? PhysicalRumbleOutput else {
      return false
    }
    do {
      try rumbleOutput.sendPhysicalRumble(
        handle: handle,
        left: left,
        right: right,
        lt: lt,
        rt: rt
      )
      return true
    } catch {
      print("[DevicePipeline] Rumble send failed for \(identifier): \(error)")
      return false
    }
  }

  func hidRumbleReport(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8)
    -> PhysicalHIDOutputReport?
  {
    guard let rumbleOutput = parser as? PhysicalHIDRumbleOutput else { return nil }
    return rumbleOutput.physicalRumbleReport(left: left, right: right, lt: lt, rt: rt)
  }

  // MARK: - Private USB pipeline

  private func startUSBPipeline(vendorID: UInt16, productID: UInt16) async {
    guard let context = usbContext else {
      print("[DevicePipeline] Missing USBContext for \(identifier)")
      isActive = false
      return
    }

    var openAttempt: Int = 0
    while isActive {
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
      consecutiveUSBIOErrors = 0

      guard await performUSBHandshake(handle: handle) else {
        // Try again while active, but slow down to avoid hot loops that launchd may kill
        // as "inefficient".
        openAttempt += 1
        let delay = min(UInt64(4_000_000_000), UInt64(250_000_000) << min(openAttempt, 4))
        try? await Task.sleep(nanoseconds: delay)
        continue
      }

      await runUSBInputLoop(handle: handle)

      if !isActive { return }

      // Prevent immediate reopen loops.
      openAttempt += 1
      let delay = min(UInt64(4_000_000_000), UInt64(250_000_000) << min(openAttempt, 4))
      try? await Task.sleep(nanoseconds: delay)
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
    if transportProfile.needsSetConfiguration {
      let cfg = (try? handle.getConfiguration()) ?? 0
      if cfg != 1 {
        try handle.setConfiguration(1)
      }
    }
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
    let inEndpoint = transportProfile.inputEndpoint
    var lastKeepAliveNs = DispatchTime.now().uptimeNanoseconds
    print("[DevicePipeline] Starting USB input loop:" + " \(identifier)"
          + " inEP=0x\(String(inEndpoint, radix: 16))")

    if transportProfile.postHandshakeSettleNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: transportProfile.postHandshakeSettleNanoseconds)
    }

    while isActive {
      let loopStartNs = DispatchTime.now().uptimeNanoseconds
      if !sleepGate.isSleeping,
        shouldSendKeepAlive(lastKeepAliveNs: lastKeepAliveNs, now: loopStartNs)
      {
        lastKeepAliveNs = loopStartNs
        runKeepAlive(handle: handle)
      }
      var shouldBreak = false
      var shouldThrottleIdle = false
      do {
        let bytes = try readInterrupt(handle: handle, inEndpoint: inEndpoint)
        consecutiveUSBIOErrors = 0
        appendToPacketLog(bytes: bytes, direction: "rx")
        let events = try parseEvents(from: bytes)
        await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
      } catch let error as USBError where error.isTimeout {
        // No data in this interval; throttle below to avoid a hot timeout loop.
        shouldThrottleIdle = true
      } catch let error as USBError where error.isNoDevice {
        print("[DevicePipeline] Device disconnected:" + " \(identifier)")
        shouldBreak = true
      } catch let error as USBError where error.isIOError {
        consecutiveUSBIOErrors += 1

        let now = DispatchTime.now().uptimeNanoseconds
        if now &- lastUSBIOErrorLogNs >= usbIOErrorLogIntervalNs {
          lastUSBIOErrorLogNs = now
          print(
            "[DevicePipeline] USB I/O error (will recover)" + " for \(identifier): \(error)"
              + " (consecutive=\(consecutiveUSBIOErrors))"
          )
        }

        // Back off aggressively to avoid triggering launchd "inefficient" kills.
        let exp = min(max(0, consecutiveUSBIOErrors - 1), 4)
        let backoff = min(usbIOErrorBackoffMaxNs, usbIOErrorBackoffBaseNs << exp)
        try? await Task.sleep(nanoseconds: backoff)

        if consecutiveUSBIOErrors >= usbIOErrorReconnectThreshold {
          print("[DevicePipeline] Too many USB I/O errors — reconnecting:" + " \(identifier)")
          shouldBreak = true
        }
      } catch {
        // Unknown failures: slow down and let the outer loop reconnect.
        print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error) — reconnecting")
        try? await Task.sleep(nanoseconds: 250_000_000)
        shouldBreak = true
      }

      if shouldBreak { break }

      // Throttle idle timeouts only. Successful packets should dispatch at device cadence.
      let loopElapsedNs = DispatchTime.now().uptimeNanoseconds &- loopStartNs
      if shouldThrottleIdle && loopElapsedNs < usbIdleLoopCadenceNs {
        try? await Task.sleep(nanoseconds: usbIdleLoopCadenceNs &- loopElapsedNs)
      } else {
        await Task.yield()
      }
    }

    await neutralizeOutput()
    try? handle.releaseInterface(0)
    usbHandle = nil
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
  }

  private func shouldSendKeepAlive(lastKeepAliveNs: UInt64, now: UInt64) -> Bool {
    now &- lastKeepAliveNs >= keepAliveIntervalNs
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

  private func startIdleMonitor() {
    idleMonitorTask?.cancel()
    idleMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: idleMonitorIntervalNanoseconds)
        await self.evaluateIdleSleep()
      }
    }
  }

  private func evaluateIdleSleep() async {
    guard isActive else { return }
    guard
      sleepGate.idleTransition(
        currentState: currentInputState,
        now: DispatchTime.now().uptimeNanoseconds
      )
        != nil
    else { return }

    let neutralizingEvents = outputState.neutralizingEvents()
    print("[DevicePipeline] Controller sleeping after idle: \(identifier)")
    if !neutralizingEvents.isEmpty {
      await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
      updateOutputState(from: neutralizingEvents)
    }
  }

  private func handleParsedEvents(_ events: [ControllerEvent], now: UInt64) async {
    let previousState = currentInputState
    let nextState = currentInputState.applying(events: events)
    updateObservedInputState(from: events)

    switch sleepGate.handleInput(
      events: events,
      previousState: previousState,
      nextState: nextState,
      now: now
    ) {
    case .forward:
      if !externalOutputAllowed { return }
      if waitingForExternalNeutral {
        if nextState.isEffectivelyNeutral {
          waitingForExternalNeutral = false
          print("[DevicePipeline] Foreground gate re-armed after neutral: \(identifier)")
          return
        }
        if !events.isEmpty {
          waitingForExternalNeutral = false
          print(
            "[DevicePipeline] Foreground gate re-armed after first post-focus change: \(identifier)"
          )
          return
        }
        return
      }
      if !events.isEmpty {
        await dispatcher.dispatch(events: events, from: identifier)
      }
      updateOutputState(from: events)
    case .consumeWhileSleeping:
      break
    case .consumeWake:
      print("[DevicePipeline] Controller woke from sleep: \(identifier)")
    }
  }
}
