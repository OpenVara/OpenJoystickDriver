import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import Security

/// Sends HID input reports via a user-space IOHIDUserDevice.
///
/// This is a no-reboot compatibility path for apps that ignore DriverKit
/// virtual HID devices (for example, SDL apps that filter Transport="Virtual").
///
/// The user-space device uses Transport="USB" and a non-zero LocationID so it
/// looks like a normal controller to consumers.
public final class UserSpaceOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  public enum CreationError: Error, CustomStringConvertible, Sendable {
    case createFailed
    case missingEntitlement(String)

    public var description: String {
      switch self {
      case .createFailed: return "Failed to create IOHIDUserDevice"
      case .missingEntitlement(let e): return "Missing entitlement: \(e)"
      }
    }
  }

  // MARK: - OutputDispatcher

  public var suppressOutput = false

  // MARK: - HID user device

  private let profile: VirtualDeviceProfile
  private var userDevice: IOHIDUserDevice?
  private let deviceLock = NSLock()

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

  /// Last creation error (human-readable), for UI display.
  public private(set) var status: String = "off"

  public init(
    profile: VirtualDeviceProfile = .default
  ) throws {
    self.profile = profile
    try createDevice()
  }

  deinit { close() }

  public func close() {
    deviceLock.withLock { userDevice = nil }
    status = "off"
  }

  private func createDevice() throws {
    let descriptor = Data(GamepadHIDDescriptor.descriptor)

    // IMPORTANT: Keep the properties dictionary minimal. Some HID keys that are valid on
    // real devices are rejected for IOHIDUserDevice creation on newer macOS builds.
    func tryCreate(_ props: [String: Any]) -> IOHIDUserDevice? {
      IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault,
        props as CFDictionary,
        IOOptionBits(kIOHIDOptionsTypeNone)
      )
    }

    var properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: descriptor,
      kIOHIDVendorIDKey as String: NSNumber(value: profile.vendorID),
      kIOHIDProductIDKey as String: NSNumber(value: profile.productID),
      kIOHIDProductKey as String: profile.productName,
      kIOHIDManufacturerKey as String: profile.manufacturer,
      kIOHIDSerialNumberKey as String: UserSpaceVirtualDeviceConstants.serialNumber,
      kIOHIDTransportKey as String: "USB",
    ]
    properties[kIOHIDLocationIDKey as String] = NSNumber(
      value: UserSpaceVirtualDeviceConstants.locationID
    )

    var dev = tryCreate(properties)
    if dev == nil {
      // Some macOS builds reject certain HID keys for IOHIDUserDevice creation.
      // LocationID is optional; fall back to 0 and expose a precise status string.
      properties.removeValue(forKey: kIOHIDLocationIDKey as String)
      dev = tryCreate(properties)
      if dev != nil {
        status = "warning: created without LocationID (some apps may ignore this device)"
      }
    }

    guard let dev else {
      let entitlement = "com.apple.developer.hid.virtual.device"
      if !Self.hasEntitlement(entitlement) {
        status = "error: missing entitlement \(entitlement) (regenerate daemon profile)"
        throw CreationError.missingEntitlement(entitlement)
      }
      status = "error: \(CreationError.createFailed)"
      throw CreationError.createFailed
    }
    deviceLock.withLock { userDevice = dev }
    if !status.hasPrefix("warning:") { status = "on" }
  }

  private static func hasEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    guard let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else {
      return false
    }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
      return CFBooleanGetValue((value as! CFBoolean))
    }
    return false
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }
    guard let dev = deviceLock.withLock({ userDevice }) else { return }

    var report = reportLock.withLock { () -> [UInt8] in
      for event in events { applyEvent(event, deadzone: 0.15) }
      return buildReport()
    }

    let result = report.withUnsafeMutableBytes { ptr -> IOReturn in
      guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
      return IOHIDUserDeviceHandleReportWithTimeStamp(
        dev,
        0,
        base.assumingMemoryBound(to: UInt8.self),
        ptr.count
      )
    }

    if result != kIOReturnSuccess {
      status = "error: \(String(result, radix: 16))"
    } else if status.hasPrefix("error:") {
      status = "on"
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
      let dpadMask: UInt32 = 0xF << 11
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
    case .l2Digital, .r2Digital: return nil
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
