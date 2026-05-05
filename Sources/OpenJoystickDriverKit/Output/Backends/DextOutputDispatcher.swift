import Foundation
import IOKit
import IOKit.hid

/// Sends HID reports to the DriverKit virtual gamepad via `IOHIDDeviceSetReport`.
///
/// The daemon finds the virtual device by VID/PID through IOHIDManager,
/// then sends output reports. The dext's `setReport` override
/// relays them as input reports via `handleReport`.
///
/// If ``connect()`` returns `false`, ``dispatch(events:from:)`` auto-retries
/// on every call until the dext loads.
public final class DextOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  /// Posted when DriverKit injection is unstable (typically during sysext replacement/upgrade).
  public static let dextUnstableNotification = Notification.Name("OpenJoystickDriver.DextUnstable")

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - `reportLock` guards all mutable report state (buttons, sticks, triggers, hat)
  // - `connectionLock` guards `hidDevice` and `hidManager`
  // - `suppressOutput` is only written from the main actor (XPC handler)

  // MARK: - OutputDispatcher

  /// When true, report injection is suppressed (e.g. during developer packet capture).
  public var suppressOutput = false

  // MARK: - HID device connection

  /// Identity of the virtual gamepad presented to the OS.
  private let profile: VirtualDeviceProfile
  private let format: any VirtualGamepadReportFormat
  private var hidDevice: IOHIDDevice?
  private var hidManager: IOHIDManager?
  private let connectionLock = NSLock()
  private var enabled: Bool = true
  private var nextAutoRetryConnectNs: UInt64 = 0
  private var autoRetryBackoffNs: UInt64 = 250_000_000  // 250ms
  private var lastConnectionLostLogNs: UInt64 = 0

  // MARK: - Optional exclusive-seize (Compatibility mode)

  private let seizeLock = NSLock()
  private var seizedDevice: IOHIDDevice?
  private var seizedManager: IOHIDManager?
  private var compatibilitySeizeRequested = false
  private var seizeRetryScheduled = false

  // MARK: - Stability tracking

  private let stabilityLock = NSLock()
  private var failureTimestamps: [UInt64] = []
  private var lastUnstablePost: UInt64 = 0

  // MARK: - Output stats (for diagnostics)

  private let statsLock = NSLock()
  private var setReportAttempts: Int = 0
  private var setReportSuccesses: Int = 0
  private var setReportFailures: Int = 0
  private var lastSetReportError: IOReturn?
  private var connectionAttempts: Int = 0
  private var connectionSuccesses: Int = 0
  private var connectionFailures: Int = 0
  private var lastConnectionError: IOReturn?
  private var lastDiscoverySummary: String?

  // MARK: - Report state

  private let reportLock = NSLock()
  private var buttons: UInt32 = 0
  private var leftStickX: Int16 = 0
  private var leftStickY: Int16 = 0
  private var rightStickX: Int16 = 0
  private var rightStickY: Int16 = 0
  private var leftTrigger: Int16 = 0
  private var rightTrigger: Int16 = 0
  private var hat: GamepadHIDDescriptor.Hat = .neutral

  private static let relayMagic: [UInt8] = [0x4F, 0x4A]  // "OJ"
  // MARK: - Init / deinit

  /// Creates a new DextOutputDispatcher.
  ///
  /// - Parameters:
  ///   - profile: Virtual device identity used for HID device matching.
  public init(profile: VirtualDeviceProfile = .openJoystickDriver) {
    self.profile = profile
    self.format = OJDGenericGamepadFormat()
  }

  deinit { closeDevice() }

  // MARK: - Connection management

  /// Enables or disables DriverKit output injection.
  ///
  /// When disabled, any open IOHID device handle is closed and future dispatch calls are no-ops.
  public func setEnabled(_ isEnabled: Bool) {
    let shouldClose = connectionLock.withLock { () -> Bool in
      let changed = enabled != isEnabled
      enabled = isEnabled
      return changed && !isEnabled
    }
    if shouldClose { closeDevice() }
  }

  public func isConnected() -> Bool {
    connectionLock.withLock { hidDevice != nil }
  }

  /// Best-effort: when enabled, tries to seize the DriverKit virtual HID device so
  /// SDL/IOKit apps prefer the user-space controller (Compatibility mode) and do not
  /// accidentally open the idle DriverKit device.
  ///
  /// This does not uninstall/disable the system extension; it only attempts exclusive open.
  public func setCompatibilitySeizeEnabled(_ enabled: Bool) {
    if enabled {
      let shouldAttempt = seizeLock.withLock { () -> Bool in
        compatibilitySeizeRequested = true
        return seizedDevice == nil
      }
      if shouldAttempt { attemptCompatibilitySeize() }
    } else {
      let (oldDevice, oldMgr) = seizeLock.withLock { () -> (IOHIDDevice?, IOHIDManager?) in
        compatibilitySeizeRequested = false
        seizeRetryScheduled = false
        let d = seizedDevice
        let m = seizedManager
        seizedDevice = nil
        seizedManager = nil
        return (d, m)
      }
      if let device = oldDevice { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) }
      if let mgr = oldMgr { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
  }

  private func attemptCompatibilitySeize() {
    let shouldTry = seizeLock.withLock { compatibilitySeizeRequested && seizedDevice == nil }
    guard shouldTry else { return }

    if let (device, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) {
      seizeLock.withLock {
        seizedDevice = device
        seizedManager = mgr
        seizeRetryScheduled = false
      }
      return
    }

    let shouldSchedule = seizeLock.withLock { () -> Bool in
      guard compatibilitySeizeRequested && seizedDevice == nil && !seizeRetryScheduled else {
        return false
      }
      seizeRetryScheduled = true
      return true
    }
    guard shouldSchedule else { return }

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.seizeLock.withLock { self.seizeRetryScheduled = false }
      self.attemptCompatibilitySeize()
    }
  }

  @discardableResult public func connect() -> Bool {
    guard connectionLock.withLock({ enabled }) else { return false }
    guard let (device, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeNone)) else {
      print("[DextOutputDispatcher] Virtual gamepad not found — not installed or not approved")
      return false
    }
    connectionLock.withLock {
      hidDevice = device
      hidManager = mgr
    }
    print(
      "[DextOutputDispatcher] Connected to virtual gamepad (VID:\(profile.vendorID) PID:\(profile.productID))"
    )
    return true
  }

  private func closeDevice() {
    let (oldDevice, oldMgr) = connectionLock.withLock { () -> (IOHIDDevice?, IOHIDManager?) in
      let d = hidDevice
      let m = hidManager
      hidDevice = nil
      hidManager = nil
      return (d, m)
    }
    if let device = oldDevice { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    if let mgr = oldMgr { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
  }

  private func findDevice(openOptions: IOOptionBits) -> (IOHIDDevice, IOHIDManager)? {
    recordConnectionAttempt()
    // Do NOT match by VID/PID.
    //
    // During development and during sysext replacement/upgrade, the installed dext may be an
    // older build with a different VID/PID than the Swift layer expects. Also, our virtual
    // identity is intentionally not tied to any real controller's VID/PID.
    //
    // Instead, broadly enumerate HID devices and identify the dext via IOUserClass / serial.
    func openManager(_ matching: CFDictionary?) -> IOHIDManager {
      let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
      IOHIDManagerSetDeviceMatching(mgr, matching)
      let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      if openResult != kIOReturnSuccess {
        print("[DextOutputDispatcher] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
      }
      return mgr
    }

    func copyDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
      guard let rawDevices = IOHIDManagerCopyDevices(mgr) else { return [] }
      let count = CFSetGetCount(rawDevices)
      guard count > 0 else { return [] }
      var values = [UnsafeRawPointer?](repeating: nil, count: count)
      CFSetGetValues(rawDevices, &values)
      return values.compactMap { raw in
        guard let raw else { return nil }
        return unsafeBitCast(raw, to: IOHIDDevice.self)
      }
    }

    func copyServiceDevices() -> [IOHIDDevice] {
      var iterator: io_iterator_t = 0
      let kr = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("AppleUserHIDDevice"),
        &iterator
      )
      guard kr == KERN_SUCCESS else { return [] }
      defer { IOObjectRelease(iterator) }

      var result: [IOHIDDevice] = []
      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }
        if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
          result.append(device)
        }
      }
      return result
    }

    func registryString(_ service: io_object_t, _ key: String) -> String? {
      let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue()
      return value as? String
    }

    func registryInt(_ service: io_object_t, _ key: String) -> Int {
      let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue()
      return value as? Int ?? 0
    }

    func findServiceDevice(openOptions: IOOptionBits) -> (IOHIDDevice, IOReturn)? {
      var iterator: io_iterator_t = 0
      let kr = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("AppleUserHIDDevice"),
        &iterator
      )
      guard kr == KERN_SUCCESS else { return nil }
      defer { IOObjectRelease(iterator) }

      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }

        let serial = registryString(service, kIOHIDSerialNumberKey as String)
        if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { continue }

        let ioUserClass = registryString(service, "IOUserClass")
        let vendorID = registryInt(service, kIOHIDVendorIDKey as String)
        let productID = registryInt(service, kIOHIDProductIDKey as String)
        let productName = registryString(service, kIOHIDProductKey as String)
        let manufacturer = registryString(service, kIOHIDManufacturerKey as String)
        let location = registryInt(service, kIOHIDLocationIDKey as String)

        var score = 0
        if ioUserClass == "OpenJoystickVirtualHIDDevice" { score += 1_000_000 }
        if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { score += 100_000 }
        if location == Int(VirtualDeviceIdentityConstants.driverKitLocationID) { score += 10_000 }
        if vendorID == profile.vendorID && productID == profile.productID { score += 50_000 }
        if productName == profile.productName { score += 5_000 }
        if manufacturer == profile.manufacturer { score += 1_000 }
        guard score > 0, let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
          continue
        }

        let ret = IOHIDDeviceOpen(device, openOptions)
        recordDiscoverySummary(
          "service-open \(productName ?? "?")|\(serial ?? "?")|\(ioUserClass ?? "?")|\(vendorID):\(productID)|score=\(score) ret=\(String(format: "0x%08x", UInt32(bitPattern: ret)))"
        )
        return (device, ret)
      }
      return nil
    }

    // Broad match first. On recent macOS/Swift toolchains the usage-filtered
    // IOHIDManager query can omit the DriverKit HID service even though a broad
    // query exposes it with the expected serial, VID/PID, product, and IOUserClass.
    let mgr = openManager(nil)
    let managerDevices = copyDevices(mgr)
    let devices = managerDevices.isEmpty ? copyServiceDevices() : managerDevices

    guard !devices.isEmpty else {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      recordConnectionResult(kIOReturnNotFound)
      return nil
    }

    func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
      IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
      IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
    }

    func score(_ device: IOHIDDevice) -> Int {
      // Prefer the DriverKit virtual device and avoid matching the user-space IOHIDUserDevice
      // (they share VID/PID for compatibility).
      let ioUserClass = strProp(device, "IOUserClass")
      let serial = strProp(device, kIOHIDSerialNumberKey as String)
      let location = intProp(device, kIOHIDLocationIDKey as String)
      let vendorID = intProp(device, kIOHIDVendorIDKey as String)
      let productID = intProp(device, kIOHIDProductIDKey as String)
      let productName = strProp(device, kIOHIDProductKey as String)
      let manufacturer = strProp(device, kIOHIDManufacturerKey as String)

      if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) {
        return Int.min / 2
      }
      if ioUserClass == "IOHIDUserDevice" {
        return Int.min / 2
      }
      // Extra guard: our user-space devices live in the OJ namespace.
      let rawLocation = UInt32(truncatingIfNeeded: location)
      if rawLocation != VirtualDeviceIdentityConstants.driverKitLocationID
        && (rawLocation & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace
      {
        return Int.min / 2
      }

      var s = 0
      if ioUserClass == "OpenJoystickVirtualHIDDevice" { s += 1_000_000 }
      if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { s += 100_000 }
      if location == Int(VirtualDeviceIdentityConstants.driverKitLocationID) { s += 10_000 }
      if vendorID == profile.vendorID && productID == profile.productID { s += 50_000 }
      if productName == profile.productName { s += 5_000 }
      if manufacturer == profile.manufacturer { s += 1_000 }

      // If we don't have any strong indicator that this is our dext device,
      // do not treat it as a candidate. Otherwise we risk opening a real controller
      // and blasting it with output reports.
      if s == 0 { return Int.min / 2 }

      if (strProp(device, kIOHIDTransportKey as String) ?? "") == "USB" { s += 100 }
      return s
    }

    let candidates = devices
      .map { ($0, score($0)) }
      .sorted { a, b in a.1 > b.1 }

    let summary = candidates.prefix(6).map { device, score in
      let product = strProp(device, kIOHIDProductKey as String) ?? "?"
      let serial = strProp(device, kIOHIDSerialNumberKey as String) ?? "?"
      let ioUserClass = strProp(device, "IOUserClass") ?? "?"
      let vendorID = intProp(device, kIOHIDVendorIDKey as String)
      let productID = intProp(device, kIOHIDProductIDKey as String)
      return "\(product)|\(serial)|\(ioUserClass)|\(vendorID):\(productID)|score=\(score)"
    }.joined(separator: "; ")
    recordDiscoverySummary("devices=\(devices.count), candidates=\(candidates.count), top=[\(summary)]")

    var lastOpenResult: IOReturn = kIOReturnNotFound
    for (device, s) in candidates {
      if s <= Int.min / 4 { continue }  // filtered (likely our user-space device)
      let ret = IOHIDDeviceOpen(device, openOptions)
      recordDiscoverySummary(
        "open \(strProp(device, kIOHIDProductKey as String) ?? "?") score=\(s) ret=\(String(format: "0x%08x", UInt32(bitPattern: ret)))"
      )
      lastOpenResult = ret
      if ret == kIOReturnSuccess {
        recordConnectionResult(kIOReturnSuccess)
        return (device, mgr)
      }
    }

    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    recordConnectionResult(lastOpenResult)
    return nil
  }

  // MARK: - OutputDispatcher

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }
    guard connectionLock.withLock({ enabled }) else { return }

    var device = connectionLock.withLock { hidDevice }

    if device == nil {
      let now = DispatchTime.now().uptimeNanoseconds
      let shouldAttempt = connectionLock.withLock { now >= nextAutoRetryConnectNs }
      if shouldAttempt {
        if let (newDevice, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeNone)) {
          device = newDevice
          print("[DextOutputDispatcher] Auto-retry connected to virtual gamepad")
          connectionLock.withLock {
            hidDevice = newDevice
            hidManager = mgr
            nextAutoRetryConnectNs = 0
            autoRetryBackoffNs = 250_000_000
          }
        } else {
          connectionLock.withLock {
            nextAutoRetryConnectNs = now &+ autoRetryBackoffNs
            autoRetryBackoffNs = min(autoRetryBackoffNs &* 2, 5_000_000_000)  // cap at 5s
          }
        }
      }
    }
    guard let device else { return }

    let reports = reportLock.withLock { () -> [(CFIndex, [UInt8])] in
      for event in events { applyEvent(event, deadzone: 0.15) }
      let secondaryReports = events.compactMap { xboxGuideReport(for: $0) }
      return [primaryOutputReport()] + secondaryReports
    }

    var lastResult: IOReturn = kIOReturnSuccess
    for (reportID, payload) in reports {
      var report = payload
      let result = report.withUnsafeMutableBytes { ptr -> IOReturn in
        guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
        return IOHIDDeviceSetReport(
          device,
          kIOHIDReportTypeOutput,
          reportID,
          base.assumingMemoryBound(to: UInt8.self),
          ptr.count
        )
      }
      recordSetReportResult(result)
      if result != kIOReturnSuccess { lastResult = result }
    }

    // kIOReturnNotOpen (0xe00002cd): device handle went stale during sysext replacement.
    // The dext process cycles through device instances on crash/rematch; reconnecting
    // picks up the latest instance.
    if lastResult == kIOReturnNotAttached || lastResult == kIOReturnNoDevice
      || lastResult == IOReturn(bitPattern: 0xe000_02cd)
    {
      let now = DispatchTime.now().uptimeNanoseconds
      let shouldLog = connectionLock.withLock { () -> Bool in
        // Rate-limit to avoid log spam and "inefficient" kills.
        if now &- lastConnectionLostLogNs < 10_000_000_000 { return false }
        lastConnectionLostLogNs = now
        return true
      }
      if shouldLog { print("[DextOutputDispatcher] Connection lost (\(lastResult)); will reconnect") }
      recordFailure(now: now)
      closeDevice()
      connectionLock.withLock {
        nextAutoRetryConnectNs = now &+ autoRetryBackoffNs
      }
    } else if lastResult != kIOReturnSuccess {
      // Keep this quiet; repeated failures are handled via stats + fallback mode.
    }
  }

  public func outputStatsSnapshot() -> XPCDriverKitOutputStats {
    statsLock.withLock {
      let err = lastSetReportError.map { String(format: "0x%08x", UInt32(bitPattern: $0)) }
      return XPCDriverKitOutputStats(
        attempts: setReportAttempts,
        successes: setReportSuccesses,
        failures: setReportFailures,
        lastErrorHex: err,
        connectionAttempts: connectionAttempts,
        connectionSuccesses: connectionSuccesses,
        connectionFailures: connectionFailures,
        lastConnectionErrorHex: lastConnectionError.map {
          String(format: "0x%08x", UInt32(bitPattern: $0))
        },
        lastDiscoverySummary: lastDiscoverySummary
      )
    }
  }

  private func recordDiscoverySummary(_ summary: String) {
    statsLock.withLock {
      lastDiscoverySummary = String(summary.prefix(500))
    }
  }

  private func recordConnectionAttempt() {
    statsLock.withLock {
      connectionAttempts += 1
    }
  }

  private func recordConnectionResult(_ result: IOReturn) {
    statsLock.withLock {
      if result == kIOReturnSuccess {
        connectionSuccesses += 1
      } else {
        connectionFailures += 1
        lastConnectionError = result
      }
    }
  }

  private func recordFailure(now: UInt64) {
    // Consider the dext unstable if we see lots of abort/not-open errors in a short window.
    // This commonly happens while the OS is replacing the system extension.
    let windowNs: UInt64 = 5_000_000_000  // 5s
    let threshold = 20
    let cooldownNs: UInt64 = 10_000_000_000  // 10s

    stabilityLock.withLock {
      failureTimestamps.append(now)

      // Prune old events.
      let cutoff = now &- windowNs
      if failureTimestamps.count > 512 {
        failureTimestamps.removeFirst(failureTimestamps.count - 512)
      }
      while let first = failureTimestamps.first, first < cutoff {
        failureTimestamps.removeFirst()
      }

      if failureTimestamps.count >= threshold && (now &- lastUnstablePost) > cooldownNs {
        lastUnstablePost = now
        NotificationCenter.default.post(name: Self.dextUnstableNotification, object: nil)
      }
    }
  }

  private func recordSetReportResult(_ result: IOReturn) {
    // DriverKit's HID relay can return kIOReturnAborted after delivering the input report
    // through handleReport(). Self-test verifies delivery via input value/report deltas, so
    // count this as accepted for UI health instead of surfacing a false failure.
    let accepted = result == kIOReturnSuccess || result == kIOReturnAborted
    statsLock.withLock {
      setReportAttempts += 1
      if accepted {
        setReportSuccesses += 1
      } else {
        setReportFailures += 1
        lastSetReportError = result
      }
    }
  }

  // MARK: - Event application (called inside reportLock.withLock)

  private func applyEvent(_ event: ControllerEvent, deadzone: Float) {
    switch event {
    case .buttonPressed(let btn): if let bit = buttonBit(for: btn) { buttons |= (1 << bit) }
    case .buttonReleased(let btn): if let bit = buttonBit(for: btn) { buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      leftStickX = axisValue(x, deadzone: deadzone)
      leftStickY = axisValue(y, deadzone: deadzone)
    case .rightStickChanged(let x, let y):
      rightStickX = axisValue(x, deadzone: deadzone)
      rightStickY = axisValue(y, deadzone: deadzone)
    case .leftTriggerChanged(let v): leftTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .rightTriggerChanged(let v): rightTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .dpadChanged(let dir):
      hat = hatValue(for: dir)
      // Dual encode: set D-pad button bits 11–14 alongside the hat switch.
      let dpadMask: UInt32 = 0xF << 11  // bits 11-14
      buttons = (buttons & ~dpadMask) | GamepadHIDDescriptor.dpadButtonBits(for: hat)
    }
  }

  // MARK: - Report construction (called inside reportLock.withLock)

  private func primaryOutputReport() -> (CFIndex, [UInt8]) {
    let reportID: CFIndex = {
      if let rid = format.inputReportID, rid != 0 { return CFIndex(rid) }
      return 0
    }()
    return (reportID, buildPrimaryReportPayload())
  }

  private func buildPrimaryReportPayload() -> [UInt8] {
    let state = VirtualGamepadState(
      buttons: buttons,
      leftStickX: leftStickX,
      leftStickY: leftStickY,
      rightStickX: rightStickX,
      rightStickY: rightStickY,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger,
      hat: hat
    )

    // IOHIDDeviceSetReport does not take a report-id byte in the buffer; report IDs
    // are encoded by the reportID argument. Our dext parses output report bytes and
    // relays them as input with Report ID 1.
    let full = format.buildInputReport(from: state)
    if let rid = format.inputReportID, rid != 0, full.first == rid {
      return Array(full.dropFirst())
    }
    return full
  }

  private func xboxGuideReport(for event: ControllerEvent) -> (CFIndex, [UInt8])? {
    switch event {
    case .buttonPressed(let button) where button == .guide || button == .ps:
      return framedInputReport(reportID: 2, payload: [0x01])
    case .buttonReleased(let button) where button == .guide || button == .ps:
      return framedInputReport(reportID: 2, payload: [0x00])
    default:
      return nil
    }
  }

  private func framedInputReport(reportID: UInt8, payload: [UInt8]) -> (CFIndex, [UInt8]) {
    (1, Self.relayMagic + [reportID] + payload)
  }

  // MARK: - Button mapping (XInputHID order)

  private func buttonBit(for button: Button) -> UInt32? {
    switch button {
    case .a, .cross: return 0
    case .b, .circle: return 1
    case .x, .square: return 2
    case .y, .triangle: return 3
    case .leftBumper, .l1: return 4
    case .rightBumper, .r1: return 5
    case .leftStick: return 6
    case .rightStick: return 7
    case .start, .options: return 8
    case .back: return 9
    case .guide, .ps: return 10
    case .dpadUp: return 11
    case .dpadDown: return 12
    case .dpadLeft: return 13
    case .dpadRight: return 14
    case .share: return 15
    case .l2Digital, .r2Digital: return nil  // triggers are analog only in XInputHID
    case .touchpad: return nil
    case .genericButton1, .genericButton2: return nil
    case .genericButton3, .genericButton4: return nil
    case .genericButton5, .genericButton6, .genericButton7, .genericButton8: return nil
    }
  }

  // MARK: - Axis + hat helpers

  private func axisValue(_ v: Float, deadzone: Float) -> Int16 {
    let clamped = v.clamped(to: -1...1)
    guard abs(clamped) > deadzone else { return 0 }
    return Int16(clamped * 32_767)
  }

  private func hatValue(for direction: DpadDirection) -> GamepadHIDDescriptor.Hat {
    switch direction {
    case .neutral: return .neutral
    case .north: return .north
    case .northEast: return .northEast
    case .east: return .east
    case .southEast: return .southEast
    case .south: return .south
    case .southWest: return .southWest
    case .west: return .west
    case .northWest: return .northWest
    }
  }
}
