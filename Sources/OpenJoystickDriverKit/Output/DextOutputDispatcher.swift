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

  @discardableResult public func connect() -> Bool {
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
    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: profile.vendorID,
      kIOHIDProductIDKey as String: profile.productID,
    ]
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      print("[DextOutputDispatcher] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
    }

    guard let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let device = devices.first
    else {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      return nil
    }

    let ret = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard ret == kIOReturnSuccess else {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      return nil
    }
    return (device, mgr)
  }

  // MARK: - OutputDispatcher

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }

    var device = connectionLock.withLock { hidDevice }

    if device == nil {
      if let (newDevice, mgr) = findDevice() {
        device = newDevice
        print("[DextOutputDispatcher] Auto-retry connected to virtual gamepad")
        connectionLock.withLock {
          hidDevice = newDevice
          hidManager = mgr
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

    // kIOReturnNotOpen (0xe00002cd): device handle went stale during sysext replacement.
    // The dext process cycles through device instances on crash/rematch; reconnecting
    // picks up the latest instance.
    if result == kIOReturnNotAttached || result == kIOReturnNoDevice
      || result == IOReturn(bitPattern: 0xe000_02cd)
    {
      debugPrint("[DextOutputDispatcher] Connection lost (\(result)); will reconnect")
      closeDevice()
    } else if result != kIOReturnSuccess {
      debugPrint("[DextOutputDispatcher] setReport error: \(String(result, radix: 16))")
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

// MARK: - Float clamping

extension Float {
  fileprivate func clamped(to range: ClosedRange<Float>) -> Float {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

// MARK: - Int16 little-endian byte pair

extension Int16 {
  fileprivate var littleEndianBytes: (UInt8, UInt8) {
    let le = littleEndian
    return (UInt8(le & 0xFF), UInt8((le >> 8) & 0xFF))
  }
}
