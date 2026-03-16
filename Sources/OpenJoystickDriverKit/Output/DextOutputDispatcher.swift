import Foundation
import IOKit

/// ``OutputDispatcher`` that sends HID reports to the DriverKit virtual gamepad
/// extension via an IOKit user-client connection (`IOConnectCallStructMethod`).
///
/// This is the preferred output path on macOS 13+. The daemon holds a
/// `com.apple.developer.driverkit.userclient-access` entitlement that authorises
/// it to open a user-client on the `com.openjoystickdriver.VirtualHIDDevice`
/// DriverKit extension.
///
/// If ``connect()`` returns `false` (extension not installed / not yet approved),
/// ``dispatch(events:from:)`` will auto-retry on every call until the dext loads.
///
/// Report layout is 13 bytes as defined by ``GamepadHIDDescriptor``.
///
/// - Note: Marked `@unchecked Sendable` because `io_connect_t` is a plain
///   `mach_port_t` integer. Mutable report state is protected by `stateLock`.
public final class DextOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  // MARK: - OutputDispatcher

  /// When true, report injection is suppressed (e.g. during developer packet
  /// capture). Invalidates the profile cache on change.
  public var suppressOutput = false {
    didSet { if suppressOutput != oldValue { profileCache.removeAll() } }
  }

  // MARK: - Profile cache

  private let profileStore: ProfileStore
  private struct ProfileCacheEntry { var profile: Profile; var fetchedAt: Date }
  private var profileCache: [String: ProfileCacheEntry] = [:]
  private let profileCacheTTL: TimeInterval = 1.0

  // MARK: - IOKit connection

  private static let dextBundleID = "com.openjoystickdriver.VirtualHIDDevice"
  private var connection: io_connect_t = IO_OBJECT_NULL
  private let connectionLock = NSLock()

  // MARK: - Report state

  private let stateLock = NSLock()
  private var buttons: UInt16 = 0
  private var leftStickX: Int16 = 0
  private var leftStickY: Int16 = 0
  private var rightStickX: Int16 = 0
  private var rightStickY: Int16 = 0
  private var leftTrigger: UInt8 = 0
  private var rightTrigger: UInt8 = 0
  private var hat: GamepadHIDDescriptor.Hat = .neutral

  // MARK: - Init / deinit

  public init(profileStore: ProfileStore = ProfileStore()) {
    self.profileStore = profileStore
  }

  deinit { closeConnection() }

  // MARK: - Connection management

  /// Opens an IOKit user-client connection to the DriverKit extension.
  ///
  /// - Returns: `true` when the extension is found and the connection succeeds.
  ///   When `false`, ``dispatch(events:from:)`` will auto-retry on each call.
  @discardableResult
  public func connect() -> Bool {
    let conn = makeConnection()
    connectionLock.withLock { connection = conn }
    let ok = conn != IO_OBJECT_NULL
    if ok {
      print("[DextOutputDispatcher] Connected to \(Self.dextBundleID)")
    } else {
      print("[DextOutputDispatcher] Extension not found — not installed or not approved")
    }
    return ok
  }

  private func closeConnection() {
    let old = connectionLock.withLock { () -> io_connect_t in
      let c = connection
      connection = IO_OBJECT_NULL
      return c
    }
    if old != IO_OBJECT_NULL { IOServiceClose(old) }
  }

  /// Searches for the OJD DriverKit extension in IORegistry and opens a
  /// user-client connection.
  private func makeConnection() -> io_connect_t {
    var iterator: io_iterator_t = 0
    let ret = IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching("IOUserService"),
      &iterator
    )
    guard ret == kIOReturnSuccess else { return IO_OBJECT_NULL }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
      // Filter by bundle identifier to find our specific extension.
      guard
        let propRef = IORegistryEntryCreateCFProperty(
          service,
          "CFBundleIdentifier" as CFString,
          kCFAllocatorDefault,
          0
        ),
        let bundleID = propRef.takeRetainedValue() as? String,
        bundleID == Self.dextBundleID
      else { continue }

      var conn: io_connect_t = 0
      let openRet = IOServiceOpen(service, mach_task_self_, 0, &conn)
      if openRet == kIOReturnSuccess { return conn }
    }
    return IO_OBJECT_NULL
  }

  // MARK: - OutputDispatcher

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }

    let conn = connectionLock.withLock { connection }

    // Auto-retry: dext may have loaded after the dispatcher was created.
    var activeConn = conn
    if activeConn == IO_OBJECT_NULL {
      activeConn = makeConnection()
      if activeConn != IO_OBJECT_NULL {
        print("[DextOutputDispatcher] Auto-retry connected to \(Self.dextBundleID)")
      }
      connectionLock.withLock { connection = activeConn }
    }
    guard activeConn != IO_OBJECT_NULL else { return }

    let profile = await cachedProfile(for: identifier)

    var report = stateLock.withLock { () -> [UInt8] in
      for event in events { applyEvent(event, deadzone: profile.stickDeadzone) }
      return buildReport()
    }

    let result = report.withUnsafeMutableBytes { ptr -> kern_return_t in
      IOConnectCallStructMethod(
        activeConn,
        0,  // UserClientSelector.sendReport
        ptr.baseAddress,
        ptr.count,
        nil,
        nil
      )
    }

    if result == kIOReturnNotAttached || result == kIOReturnNoDevice {
      // Extension was unloaded — clear the connection so we retry next dispatch.
      debugPrint("[DextOutputDispatcher] Connection lost (\(result)); will reconnect")
      closeConnection()
    } else if result != kIOReturnSuccess {
      debugPrint("[DextOutputDispatcher] sendReport error: \(result)")
    }
  }

  // MARK: - Profile cache

  private func cachedProfile(for identifier: DeviceIdentifier) async -> Profile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    let now = Date()
    if let entry = profileCache[key], now.timeIntervalSince(entry.fetchedAt) < profileCacheTTL {
      return entry.profile
    }
    let fresh = await profileStore.profile(for: identifier)
    profileCache[key] = ProfileCacheEntry(profile: fresh, fetchedAt: now)
    return fresh
  }

  // MARK: - Event application (called inside stateLock.withLock)

  private func applyEvent(_ event: ControllerEvent, deadzone: Float) {
    switch event {
    case .buttonPressed(let btn):
      if let bit = buttonBit(for: btn) { buttons |= (1 << bit) }
    case .buttonReleased(let btn):
      if let bit = buttonBit(for: btn) { buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      leftStickX = axisValue(x, deadzone: deadzone)
      leftStickY = axisValue(y, deadzone: deadzone)
    case .rightStickChanged(let x, let y):
      rightStickX = axisValue(x, deadzone: deadzone)
      rightStickY = axisValue(y, deadzone: deadzone)
    case .leftTriggerChanged(let v):
      leftTrigger = UInt8(clamping: Int(v.clamped(to: 0...1) * 255))
    case .rightTriggerChanged(let v):
      rightTrigger = UInt8(clamping: Int(v.clamped(to: 0...1) * 255))
    case .dpadChanged(let dir):
      hat = hatValue(for: dir)
    }
  }

  // MARK: - Report construction (called inside stateLock.withLock)

  private func buildReport() -> [UInt8] {
    var r = [UInt8](repeating: 0, count: GamepadHIDDescriptor.reportSize)
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0xFF)
    let lsxB = leftStickX.littleEndianBytes
    r[2] = lsxB.0; r[3] = lsxB.1
    let lsyB = leftStickY.littleEndianBytes
    r[4] = lsyB.0; r[5] = lsyB.1
    let rsxB = rightStickX.littleEndianBytes
    r[6] = rsxB.0; r[7] = rsxB.1
    let rsyB = rightStickY.littleEndianBytes
    r[8] = rsyB.0; r[9] = rsyB.1
    r[10] = leftTrigger
    r[11] = rightTrigger
    r[12] = hat.rawValue & 0x0F
    return r
  }

  // MARK: - Button mapping

  private func buttonBit(for button: Button) -> UInt16? {
    switch button {
    case .a, .cross:                          return 0
    case .b, .circle:                         return 1
    case .x, .square:                         return 2
    case .y, .triangle:                       return 3
    case .leftBumper, .l1:                    return 4
    case .rightBumper, .r1:                   return 5
    case .leftStick:                          return 6
    case .rightStick:                         return 7
    case .start, .options:                    return 8
    case .back, .share:                       return 9
    case .guide, .ps:                         return 10
    case .touchpad:                           return 11
    case .genericButton1:                     return 12
    case .genericButton2:                     return 13
    case .genericButton3:                     return 14
    case .genericButton4:                     return 15
    case .genericButton5, .genericButton6,
         .genericButton7, .genericButton8:    return nil
    case .l2Digital, .r2Digital:              return nil
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return nil
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
    case .neutral:   return .neutral
    case .north:     return .north
    case .northEast: return .northEast
    case .east:      return .east
    case .southEast: return .southEast
    case .south:     return .south
    case .southWest: return .southWest
    case .west:      return .west
    case .northWest: return .northWest
    }
  }
}

// MARK: - Float clamping

private extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

// MARK: - Int16 little-endian byte pair

private extension Int16 {
  var littleEndianBytes: (UInt8, UInt8) {
    let le = littleEndian
    return (UInt8(le & 0xFF), UInt8((le >> 8) & 0xFF))
  }
}
