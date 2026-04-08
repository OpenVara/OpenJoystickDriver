import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import Security
import Darwin

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
  private let format: any VirtualGamepadReportFormat
  private let registryLock = NSLock()

  private final class Entry {
    let device: IOHIDUserDevice
    let lock = NSLock()
    var state = VirtualGamepadState()

    init(device: IOHIDUserDevice) { self.device = device }
  }

  /// One user-space IOHIDUserDevice per connected physical controller.
  ///
  /// Keyed by the physical identifier provided by the input pipeline.
  private var entries: [DeviceIdentifier: Entry] = [:]

  // MARK: - Report state

  /// Last creation error (human-readable), for UI display.
  public private(set) var status: String = "off"

  public init(
    profile: VirtualDeviceProfile = .default,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat()
  ) throws {
    self.profile = profile
    self.format = format
    // Device(s) are created lazily on first dispatch for each physical controller.
  }

  deinit { close() }

  public func close() {
    registryLock.withLock { entries.removeAll() }
    status = "off"
  }

  private func recomputeStatusLocked() {
    if entries.isEmpty {
      if !status.hasPrefix("error:") { status = "off" }
      return
    }
    if !status.hasPrefix("error:") {
      status = "on (devices=\(entries.count))"
    }
  }

  private func createDevice(for identifier: DeviceIdentifier) throws -> IOHIDUserDevice {
    let descriptor = Data(format.descriptor)
    let serialNumber = UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)
    let locationID = UserSpaceVirtualDeviceConstants.locationID(for: identifier)

    // IMPORTANT: Keep the properties dictionary minimal. Some HID keys that are valid on
    // real devices are rejected for IOHIDUserDevice creation on newer macOS builds.
    func tryCreate(_ props: [String: Any]) -> IOHIDUserDevice? {
      IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault,
        props as CFDictionary,
        IOOptionBits(kIOHIDOptionsTypeNone)
      )
    }

    let baseProperties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: descriptor,
      kIOHIDVendorIDKey as String: NSNumber(value: profile.vendorID),
      kIOHIDProductIDKey as String: NSNumber(value: profile.productID),
      kIOHIDVersionNumberKey as String: NSNumber(value: profile.versionNumber),
      kIOHIDProductKey as String: profile.productName,
      kIOHIDManufacturerKey as String: profile.manufacturer,
      kIOHIDSerialNumberKey as String: serialNumber,
      kIOHIDTransportKey as String: "USB",
      kIOHIDMaxInputReportSizeKey as String: NSNumber(
        value: (format.inputReportID == nil) ? format.inputReportPayloadSize : (format.inputReportPayloadSize + 1)
      ),
    ]

    let usageProps: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: NSNumber(value: Int(kHIDPage_GenericDesktop)),
      kIOHIDPrimaryUsageKey as String: NSNumber(value: Int(kHIDUsage_GD_GamePad)),
      kIOHIDDeviceUsagePairsKey as String: [[
        kIOHIDDeviceUsagePageKey as String: NSNumber(value: Int(kHIDPage_GenericDesktop)),
        kIOHIDDeviceUsageKey as String: NSNumber(value: Int(kHIDUsage_GD_GamePad)),
      ]],
    ]

    let noPairsUsageProps: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: NSNumber(value: Int(kHIDPage_GenericDesktop)),
      kIOHIDPrimaryUsageKey as String: NSNumber(value: Int(kHIDUsage_GD_GamePad)),
    ]

    let attemptVariants: [(label: String, props: [String: Any])] = [
      ("usage+pairs", baseProperties.merging(usageProps) { a, _ in a }),
      ("usage(no-pairs)", baseProperties.merging(noPairsUsageProps) { a, _ in a }),
      ("no-usage", baseProperties),
    ]
    // Some macOS builds reject certain LocationID values for IOHIDUserDevice creation.
    // Try the computed namespaced LocationID first, then a small stable fallback.
    let candidateLocationIDs: [UInt32] = [
      locationID,
      0x1000_0002,
    ]

    var dev: IOHIDUserDevice?
    attemptLoop: for variant in attemptVariants {
      var properties = variant.props

      for loc in candidateLocationIDs {
        properties[kIOHIDLocationIDKey as String] = NSNumber(value: Int64(loc))
        dev = tryCreate(properties)
        if dev != nil {
          break attemptLoop
        }
      }

      // LocationID is optional; try without it.
      properties.removeValue(forKey: kIOHIDLocationIDKey as String)
      dev = tryCreate(properties)
      if dev != nil {
        break attemptLoop
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
    return dev
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

    var entry: Entry? = registryLock.withLock { entries[identifier] }
    if entry == nil {
      do {
        let dev = try createDevice(for: identifier)
        let newEntry = Entry(device: dev)
        registryLock.withLock {
          entries[identifier] = newEntry
          if !status.hasPrefix("error:") { status = "on" }
          recomputeStatusLocked()
        }
        entry = newEntry
      } catch {
        status = "error: \(error)"
        return
      }
    }

    guard let entry else { return }

    let report = entry.lock.withLock { () -> [UInt8] in
      for event in events { applyEvent(event, deadzone: 0.15, state: &entry.state) }
      return format.buildInputReport(from: entry.state)
    }

    let result = report.withUnsafeBytes { ptr -> IOReturn in
      guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
      return IOHIDUserDeviceHandleReportWithTimeStamp(
        entry.device,
        mach_absolute_time(),
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

  private func applyEvent(_ event: ControllerEvent, deadzone: Float, state: inout VirtualGamepadState) {
    switch event {
    case .buttonPressed(let btn):
      if let bit = buttonBit(for: btn) { state.buttons |= (1 << bit) }
    case .buttonReleased(let btn):
      if let bit = buttonBit(for: btn) { state.buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      state.leftStickX = axisValue(x, deadzone: deadzone)
      state.leftStickY = axisValue(y, deadzone: deadzone)
    case .rightStickChanged(let x, let y):
      state.rightStickX = axisValue(x, deadzone: deadzone)
      state.rightStickY = axisValue(y, deadzone: deadzone)
    case .leftTriggerChanged(let v):
      state.leftTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .rightTriggerChanged(let v):
      state.rightTrigger = Int16(v.clamped(to: 0...1) * 32_767)
    case .dpadChanged(let dir):
      state.hat = hatValue(for: dir)
      let dpadMask: UInt32 = 0xF << 11
      state.buttons = (state.buttons & ~dpadMask) | GamepadHIDDescriptor.dpadButtonBits(for: state.hat)
    }
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
