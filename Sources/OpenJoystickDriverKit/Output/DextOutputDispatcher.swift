import Foundation
import IOKit
import IOKit.hid

/// Sends HID reports to the DriverKit virtual gamepad via `IOHIDDeviceSetReport`.
///
/// The daemon finds the virtual device by VID/PID through IOHIDManager,
/// then sends 15-byte output reports. The dext's `setReport` override
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
  private var hidDevice: IOHIDDevice?
  private var hidManager: IOHIDManager?
  private let connectionLock = NSLock()
  private var enabled: Bool = true
  private var nextAutoRetryConnectNs: UInt64 = 0
  private var autoRetryBackoffNs: UInt64 = 250_000_000  // 250ms
  private var lastConnectionLostLogNs: UInt64 = 0

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

  // MARK: - Init / deinit

  /// Creates a new DextOutputDispatcher.
  ///
  /// - Parameters:
  ///   - profile: Virtual device identity used for HID device matching.
  public init(profile: VirtualDeviceProfile = .default) { self.profile = profile }

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

  @discardableResult public func connect() -> Bool {
    guard connectionLock.withLock({ enabled }) else { return false }
    guard let (device, mgr) = findDevice() else {
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

  private func findDevice() -> (IOHIDDevice, IOHIDManager)? {
    // Do NOT match by VID/PID.
    //
    // During development and during sysext replacement/upgrade, the installed dext may be an
    // older build with a different VID/PID than the Swift layer expects. Also, our virtual
    // identity is intentionally not tied to any real controller's VID/PID.
    //
    // Instead, find by "GamePad" usage and then identify the dext via IOUserClass / serial.
    let matching: [String: Any] = [
      kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad,
    ]
    func openManager(_ matching: CFDictionary?) -> IOHIDManager {
      let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
      IOHIDManagerSetDeviceMatching(mgr, matching)
      let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      if openResult != kIOReturnSuccess {
        print("[DextOutputDispatcher] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
      }
      return mgr
    }

    func copyDevices(_ mgr: IOHIDManager) -> Set<IOHIDDevice> {
      (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
    }

    // Pass 1: fast path (GamePad usage match).
    var mgr = openManager(matching as CFDictionary)
    var devices = copyDevices(mgr)

    // Pass 2: broad match fallback. Some installed dext builds may not match under usage filtering
    // during replacement/upgrade or when app/dext identities are temporarily out of sync.
    if devices.isEmpty {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      mgr = openManager(nil)
      devices = copyDevices(mgr)
    }

    guard !devices.isEmpty else {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
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
      let product = strProp(device, kIOHIDProductKey as String)
      let manufacturer = strProp(device, kIOHIDManufacturerKey as String)

      if serial == UserSpaceVirtualDeviceConstants.serialNumber {
        return Int.min / 2
      }
      if ioUserClass == "IOHIDUserDevice" {
        return Int.min / 2
      }

      var s = 0
      if ioUserClass == "OpenJoystickVirtualHIDDevice" { s += 1_000_000 }
      if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { s += 100_000 }
      if location == Int(VirtualDeviceIdentityConstants.driverKitLocationID) { s += 10_000 }

      // Fallback: some macOS builds do not expose IOUserClass / serial on IOHIDDevice.
      // Because we use a non-real OJD VID/PID, this is still safe.
      let vid = intProp(device, kIOHIDVendorIDKey as String)
      let pid = intProp(device, kIOHIDProductIDKey as String)
      let looksLikeOJDVirtual =
        (vid == profile.vendorID)
        && (pid == profile.productID)
        && (product == profile.productName)
        && (manufacturer == profile.manufacturer)
      if looksLikeOJDVirtual { s += 5_000 }

      // If we don't have any strong indicator that this is our dext device,
      // do not treat it as a candidate. Otherwise we risk opening a real controller
      // and blasting it with output reports.
      if s == 0 { return Int.min / 2 }

      if (strProp(device, kIOHIDTransportKey as String) ?? "") == "USB" { s += 100 }
      // Tie-breaker only: prefer devices matching our current profile identity.
      if vid == profile.vendorID && pid == profile.productID { s += 10 }
      return s
    }

    let candidates = devices
      .map { ($0, score($0)) }
      .sorted { a, b in a.1 > b.1 }

    for (device, s) in candidates {
      if s <= Int.min / 4 { continue }  // filtered (likely our user-space device)
      let ret = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
      if ret == kIOReturnSuccess { return (device, mgr) }
    }

    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
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
        if let (newDevice, mgr) = findDevice() {
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

    var report = reportLock.withLock { () -> [UInt8] in
      for event in events { applyEvent(event, deadzone: 0.15) }
      return buildReport()
    }

    let result = report.withUnsafeMutableBytes { ptr -> IOReturn in
      guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
      return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        0,
        base.assumingMemoryBound(to: UInt8.self),
        ptr.count
      )
    }

    statsLock.withLock {
      setReportAttempts += 1
      if result == kIOReturnSuccess {
        setReportSuccesses += 1
      } else {
        setReportFailures += 1
        lastSetReportError = result
      }
    }

    // Aborted (0xe00002eb): IOKit can abort in-flight operations during sysext replacement/upgrade.
    // Treat it the same as a stale handle and reconnect on the next dispatch.
    let kIOReturnAbortedValue: IOReturn = IOReturn(bitPattern: 0xe000_02eb)

    // kIOReturnNotOpen (0xe00002cd): device handle went stale during sysext replacement.
    // The dext process cycles through device instances on crash/rematch; reconnecting
    // picks up the latest instance.
    if result == kIOReturnNotAttached || result == kIOReturnNoDevice
      || result == IOReturn(bitPattern: 0xe000_02cd) || result == kIOReturnAbortedValue
    {
      let now = DispatchTime.now().uptimeNanoseconds
      let shouldLog = connectionLock.withLock { () -> Bool in
        // Rate-limit to avoid log spam and "inefficient" kills.
        if now &- lastConnectionLostLogNs < 10_000_000_000 { return false }
        lastConnectionLostLogNs = now
        return true
      }
      if shouldLog { print("[DextOutputDispatcher] Connection lost (\(result)); will reconnect") }
      recordFailure(now: now)
      closeDevice()
      connectionLock.withLock {
        nextAutoRetryConnectNs = now &+ autoRetryBackoffNs
      }
    } else if result != kIOReturnSuccess {
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
        lastErrorHex: err
      )
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

  private func buildReport() -> [UInt8] {
    var r = [UInt8](repeating: 0, count: GamepadHIDDescriptor.reportSize)
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0xFF)
    let lsxB = leftStickX.littleEndianBytes
    r[2] = lsxB.0
    r[3] = lsxB.1
    let lsyB = leftStickY.littleEndianBytes
    r[4] = lsyB.0
    r[5] = lsyB.1
    let ltB = leftTrigger.littleEndianBytes
    r[6] = ltB.0
    r[7] = ltB.1
    let rsxB = rightStickX.littleEndianBytes
    r[8] = rsxB.0
    r[9] = rsxB.1
    let rsyB = rightStickY.littleEndianBytes
    r[10] = rsyB.0
    r[11] = rsyB.1
    let rtB = rightTrigger.littleEndianBytes
    r[12] = rtB.0
    r[13] = rtB.1
    r[14] = hat.rawValue & 0x0F
    return r
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
    case .back, .share: return 9
    case .guide, .ps: return 10
    case .dpadUp: return 11
    case .dpadDown: return 12
    case .dpadLeft: return 13
    case .dpadRight: return 14
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
