import Foundation
import IOKit.hid
import IOKit.hidsystem

/// ``OutputDispatcher`` that exposes a virtual USB HID gamepad to the system
/// using ``IOHIDUserDevice``.
///
/// No Accessibility permission is required — the IOKit HID user-device API
/// is available to any process holding the
/// `com.apple.developer.hid.virtual.device` entitlement.
/// The virtual device is visible to SDL3, GCController, and any HID-aware
/// application immediately after the daemon starts.
///
/// The device lifetime is tied to this object: the virtual gamepad appears
/// when the dispatcher is initialised and disappears when it is deallocated
/// (i.e. when the daemon exits). This mirrors the IOKit driver lifecycle
/// without requiring a DriverKit extension.
///
/// - Note: Marked `@unchecked Sendable` because `IOHIDUserDevice` is a
///   Core-Foundation–style opaque object that does not conform to `Sendable`.
///   Mutable report state is protected by `stateLock.withLock { }`.
public final class IOHIDVirtualOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  // MARK: - Suppression

  /// When true all report injection is suppressed (e.g. during developer
  /// packet capture). Invalidates the profile cache on change.
  public var suppressOutput = false {
    didSet { if suppressOutput != oldValue { profileCache.removeAll() } }
  }

  // MARK: - Profile cache

  private let profileStore: ProfileStore
  private struct ProfileCacheEntry { var profile: Profile; var fetchedAt: Date }
  private var profileCache: [String: ProfileCacheEntry] = [:]
  private let profileCacheTTL: TimeInterval = 1.0

  // MARK: - HID device

  /// The IOKit virtual HID device. Nil if creation failed at init time.
  private let hidDevice: IOHIDUserDevice?

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

  // MARK: - Init

  public init(profileStore: ProfileStore = ProfileStore()) {
    self.profileStore = profileStore

    let properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: Data(GamepadHIDDescriptor.descriptor) as CFData,
      kIOHIDVendorIDKey as String: 0x0001 as CFNumber,
      kIOHIDProductIDKey as String: 0x0001 as CFNumber,
      kIOHIDVersionNumberKey as String: 0x0100 as CFNumber,
      kIOHIDProductKey as String: "OpenJoystickDriver Virtual Gamepad" as CFString,
      kIOHIDManufacturerKey as String: "OpenJoystickDriver" as CFString,
    ]

    guard
      let device = IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault,
        properties as CFDictionary,
        0
      )
    else {
      hidDevice = nil
      debugPrint("[IOHIDVirtualOutputDispatcher] Failed to create virtual HID device")
      return
    }

    hidDevice = device
    // Use a private serial queue — the main queue must not be used here
    // because init() is called synchronously on the main thread before
    // RunLoop.main.run(), and IOHIDUserDeviceActivate would deadlock
    // trying to dispatch back onto a queue that isn't draining yet.
    // Since we only send reports (no RegisterGetReport/RegisterSetReport
    // callbacks), the queue choice has no effect on functionality.
    let hidQueue = DispatchQueue(
      label: "com.openjoystickdriver.hid.userdevice",
      qos: .userInteractive
    )
    IOHIDUserDeviceSetDispatchQueue(device, hidQueue)
    IOHIDUserDeviceActivate(device)
    debugPrint("[IOHIDVirtualOutputDispatcher] Virtual gamepad device created and activated")
  }

  deinit {
    if let device = hidDevice { IOHIDUserDeviceCancel(device) }
  }

  // MARK: - OutputDispatcher

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput, let device = hidDevice else { return }

    let profile = await cachedProfile(for: identifier)

    var report = stateLock.withLock { () -> [UInt8] in
      for event in events { applyEvent(event, deadzone: profile.stickDeadzone) }
      return buildReport()
    }

    let result = IOHIDUserDeviceHandleReportWithTimeStamp(
      device,
      mach_absolute_time(),
      &report,
      CFIndex(report.count)
    )
    if result != kIOReturnSuccess {
      debugPrint("[IOHIDVirtualOutputDispatcher] handleReport error: \(result)")
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

  /// Returns the button's bit position (0-based) in the 16-bit button word,
  /// or nil when the button has no HID button mapping (e.g. d-pad or
  /// analog-only inputs that go through other report fields).
  private func buttonBit(for button: Button) -> UInt16? {
    switch button {
    // Face buttons — Xbox/PS aliases share the same bit.
    case .a, .cross:                          return 0
    case .b, .circle:                         return 1
    case .x, .square:                         return 2
    case .y, .triangle:                       return 3
    // Shoulder buttons
    case .leftBumper, .l1:                    return 4
    case .rightBumper, .r1:                   return 5
    // Stick clicks
    case .leftStick:                          return 6
    case .rightStick:                         return 7
    // Meta buttons
    case .start, .options:                    return 8
    case .back, .share:                       return 9
    case .guide, .ps:                         return 10
    // PS4 touchpad click
    case .touchpad:                           return 11
    // Generic fallbacks — map to bits 12–15; overflow is not reported.
    case .genericButton1:                     return 12
    case .genericButton2:                     return 13
    case .genericButton3:                     return 14
    case .genericButton4:                     return 15
    case .genericButton5, .genericButton6,
         .genericButton7, .genericButton8:    return nil
    // Analog-only: l2Digital/r2Digital are threshold versions of the
    // trigger axes; they are NOT reported as digital buttons in the HID
    // report (they are already in bytes 10-11 via leftTriggerChanged).
    case .l2Digital, .r2Digital:              return nil
    // D-pad directions go through the hat switch (byte 12), not buttons.
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
