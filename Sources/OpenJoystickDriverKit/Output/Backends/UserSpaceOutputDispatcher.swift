import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

/// Sends HID input reports via a user-space IOHIDUserDevice.
///
/// This is a no-reboot compatibility path for apps that ignore DriverKit
/// virtual HID devices (for example, SDL apps that filter Transport="Virtual").
///
/// The user-space device uses Transport="USB" and a non-zero LocationID so it
/// looks like a normal controller to consumers.
public final class UserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDispatching,
  @unchecked Sendable
{
  public typealias RumbleCommandHandler =
    @Sendable (DeviceIdentifier, VirtualRumbleCommand) -> Void

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
  private let primaryUsage: Int
  private let emitsXboxGuideReport: Bool
  private let routeToken: String?
  private let productNameOverride: String?
  private let registryLock = NSLock()

  private final class Entry {
    let device: IOHIDUserDevice
    let queue: DispatchQueue
    let lock = NSLock()
    var state = VirtualGamepadState()
    var lastFailure: IOReturn?
    // Counts failures since last successful report delivery.
    // Some macOS builds flip-flop error codes for a dead/invalid IOHIDUserDevice,
    // so this intentionally ignores whether the error matches the previous one.
    var consecutiveFailures: Int = 0
    var nextRecreateAttemptNs: UInt64 = 0

    init(device: IOHIDUserDevice, queue: DispatchQueue) {
      self.device = device
      self.queue = queue
    }
  }

  /// One user-space IOHIDUserDevice per connected physical controller.
  ///
  /// Keyed by the physical identifier provided by the input pipeline.
  private var entries: [DeviceIdentifier: Entry] = [:]

  // MARK: - Report state

  /// Last creation error (human-readable), for UI display.
  public private(set) var status: String = "off"
  public private(set) var lastRumbleStatus: String = "none"
  private let onRumbleCommand: RumbleCommandHandler?

  @preconcurrency
  public init(
    profile: VirtualDeviceProfile = .default,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    primaryUsage: Int? = nil,
    emitsXboxGuideReport: Bool = false,
    routeToken: String? = nil,
    productNameOverride: String? = nil,
    onRumbleCommand: RumbleCommandHandler? = nil
  ) throws {
    self.profile = profile
    self.format = format
    self.primaryUsage = primaryUsage ?? Self.defaultPrimaryUsage(for: format)
    self.emitsXboxGuideReport = emitsXboxGuideReport
    self.routeToken = routeToken
    self.productNameOverride = productNameOverride
    self.onRumbleCommand = onRumbleCommand
    // Device(s) are created lazily on first dispatch for each physical controller.
  }

  deinit { close() }

  public func close() {
    let oldEntries = registryLock.withLock { () -> [Entry] in
      let old = Array(entries.values)
      entries.removeAll()
      return old
    }
    for entry in oldEntries {
      IOHIDUserDeviceCancel(entry.device)
    }
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

  private func createDevice(for identifier: DeviceIdentifier) throws -> Entry {
    // IMPORTANT: Keep the properties dictionary minimal. Some HID keys that are valid on
    // real devices are rejected for IOHIDUserDevice creation on newer macOS builds.
    func tryCreate(_ props: [String: Any]) -> IOHIDUserDevice? {
      IOHIDUserDeviceCreateWithProperties(
        kCFAllocatorDefault,
        props as CFDictionary,
        IOOptionBits(1 << 0)
      )
    }

    let baseProperties = Self.deviceProperties(
      profile: profile,
      format: format,
      identifier: identifier,
      routeToken: routeToken,
      productNameOverride: productNameOverride
    )

    let usageProps: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: Int(kHIDPage_GenericDesktop),
      kIOHIDPrimaryUsageKey as String: primaryUsage,
      kIOHIDDeviceUsagePairsKey as String: [
        [
          kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
          kIOHIDDeviceUsageKey as String: primaryUsage,
        ],
      ],
    ]

    let noPairsUsageProps: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: Int(kHIDPage_GenericDesktop),
      kIOHIDPrimaryUsageKey as String: primaryUsage,
    ]

    let attemptVariants: [(label: String, props: [String: Any])] = [
      ("usage+pairs", baseProperties.merging(usageProps) { a, _ in a }),
      ("usage(no-pairs)", baseProperties.merging(noPairsUsageProps) { a, _ in a }),
      ("no-usage", baseProperties),
    ]
    // Some macOS builds reject certain LocationID values for IOHIDUserDevice creation.
    // Try the computed namespaced LocationID first, then a small stable fallback.
    let candidateLocationIDs: [UInt32] = [
      UserSpaceVirtualDeviceConstants.locationID(for: identifier),
      0x1000_0002,
    ]

    var dev: IOHIDUserDevice?
    attemptLoop: for variant in attemptVariants {
      var properties = variant.props

      for loc in candidateLocationIDs {
        properties[kIOHIDLocationIDKey as String] = Int64(loc)
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
    let queue = DispatchQueue(
      label:
        "com.openjoystickdriver.userspace-hid."
        + "\(routeToken ?? UserSpaceVirtualDeviceConstants.sharedRouteToken)."
        + "\(identifier.vendorID).\(identifier.productID)"
    )
    IOHIDUserDeviceRegisterGetReportBlock(dev) { type, reportID, report, reportLength in
      guard type == kIOHIDReportTypeInput else {
        reportLength.pointee = 0
        return kIOReturnUnsupported
      }
      let payloadSize = self.format.inputReportPayloadSize
      let includesReportID = self.format.inputReportID != nil
      let requiredLength = payloadSize + (includesReportID ? 1 : 0)
      guard reportLength.pointee >= requiredLength else {
        reportLength.pointee = CFIndex(requiredLength)
        return kIOReturnNoSpace
      }
      let neutral = self.format.buildInputReport(from: VirtualGamepadState())
      var offset = 0
      if let expectedReportID = self.format.inputReportID {
        guard reportID == expectedReportID else {
          reportLength.pointee = 0
          return kIOReturnUnsupported
        }
        report[0] = expectedReportID
        offset = 1
      }
      for (index, byte) in neutral.enumerated() {
        report[offset + index] = byte
      }
      reportLength.pointee = CFIndex(requiredLength)
      return kIOReturnSuccess
    }
    if let onRumbleCommand {
      IOHIDUserDeviceRegisterSetReportBlock(dev) {
        [weak self] type, reportID, report, reportLength in
        let length = max(0, Int(reportLength))
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let command = VirtualRumbleOutputReportParser.parse(
          type: type,
          reportID: reportID,
          bytes: bytes
        )
        guard let command else {
          return kIOReturnUnsupported
        }
        self?.lastRumbleStatus =
          "app report id=\(reportID) L=\(command.left) R=\(command.right) " +
          "LT=\(command.leftTrigger) RT=\(command.rightTrigger)"
        let status = self?.lastRumbleStatus ?? ""
        print("[UserSpaceOutputDispatcher] App rumble report: \(identifier) \(status)")
        onRumbleCommand(identifier, command)
        return kIOReturnSuccess
      }
    }
    IOHIDUserDeviceSetDispatchQueue(dev, queue)
    IOHIDUserDeviceActivate(dev)
    return Entry(device: dev, queue: queue)
  }

  public static func defaultPrimaryUsage(for format: any VirtualGamepadReportFormat) -> Int {
    if let xbox360 = format as? Xbox360MacHIDReportFormat {
      return Int(xbox360.topLevelUsage)
    }
    return Int(kHIDUsage_GD_GamePad)
  }

  static func deviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier,
    routeToken: String? = nil,
    productNameOverride: String? = nil
  ) -> [String: Any] {
    var properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: Data(format.descriptor),
      kIOHIDVendorIDKey as String: profile.vendorID,
      kIOHIDProductIDKey as String: profile.productID,
      kIOHIDVersionNumberKey as String: profile.versionNumber,
      kIOHIDProductKey as String: productNameOverride ?? profile.productName,
      kIOHIDManufacturerKey as String: profile.manufacturer,
      kIOHIDSerialNumberKey as String:
        UserSpaceVirtualDeviceConstants.serialNumber(for: identifier, routeToken: routeToken),
      kIOHIDTransportKey as String: "USB",
      kIOHIDMaxInputReportSizeKey as String: reportBufferSize(
        payloadSize: format.inputReportPayloadSize,
        reportID: format.inputReportID
      ),
    ]

    if let outputSize = format.outputReportPayloadSize {
      properties[kIOHIDMaxOutputReportSizeKey as String] = reportBufferSize(
        payloadSize: outputSize,
        reportID: format.outputReportID
      )
    }
    let locationID = UserSpaceVirtualDeviceConstants.locationID(
      for: identifier,
      routeToken: routeToken
    )
    properties[kIOHIDLocationIDKey as String] = Int64(locationID)
    return properties
  }

  private static func reportBufferSize(payloadSize: Int, reportID: UInt8?) -> Int {
    reportID == nil ? payloadSize : payloadSize + 1
  }

  private static func hasEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    guard let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else {
      return false
    }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
      let boolean = unsafeDowncast(value, to: CFBoolean.self)
      return CFBooleanGetValue(boolean)
    }
    return false
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    guard !suppressOutput else { return }

    let entry: Entry
    do {
      entry = try getEntry(for: identifier)
    } catch {
      status = "error: \(error)"
      return
    }

    let reports = entry.lock.withLock { () -> [[UInt8]] in
      for event in events { applyEvent(event, deadzone: 0.15, state: &entry.state) }
      let secondaryReports =
        emitsXboxGuideReport ? events.compactMap { xboxGuideReport(for: $0) } : []
      return [format.buildInputReport(from: entry.state)] + secondaryReports
    }

    var lastResult: IOReturn = kIOReturnSuccess
    for payload in reports {
      let result = payload.withUnsafeBytes { ptr -> IOReturn in
        guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
        return IOHIDUserDeviceHandleReportWithTimeStamp(
          entry.device,
          mach_absolute_time(),
          base.assumingMemoryBound(to: UInt8.self),
          ptr.count
        )
      }
      if result != kIOReturnSuccess { lastResult = result }
    }

    if lastResult != kIOReturnSuccess {
      status = "error: \(String(lastResult, radix: 16))"
      noteFailureAndMaybeRecreate(entry: entry, identifier: identifier, error: lastResult)
    } else if status.hasPrefix("error:") {
      // Clear any previous failure streak once we successfully deliver again.
      entry.lock.withLock {
        entry.lastFailure = nil
        entry.consecutiveFailures = 0
      }
      registryLock.withLock {
        if status.hasPrefix("error:") {
          recomputeStatusLocked()
        }
      }
    }
  }

  private func noteFailureAndMaybeRecreate(
    entry: Entry,
    identifier: DeviceIdentifier,
    error: IOReturn
  ) {
    let now = DispatchTime.now().uptimeNanoseconds
    let shouldRecreate = entry.lock.withLock { () -> Bool in
      if entry.nextRecreateAttemptNs > now { return false }
      entry.lastFailure = error
      entry.consecutiveFailures += 1

      // Typical "dead device" errors: recreate quickly to avoid requiring a daemon restart.
      if error == kIOReturnNotOpen || error == kIOReturnNotAttached || error == kIOReturnNoDevice
        || error == kIOReturnNotResponding
      {
        entry.nextRecreateAttemptNs = now &+ 1_000_000_000  // 1s cooldown
        entry.consecutiveFailures = 0
        return true
      }

      // For other errors, only recreate after a few consecutive failures.
      if entry.consecutiveFailures >= 3 {
        entry.nextRecreateAttemptNs = now &+ 2_000_000_000  // 2s cooldown
        entry.consecutiveFailures = 0
        return true
      }
      return false
    }

    guard shouldRecreate else { return }

    let old: Entry? = registryLock.withLock {
      // Only recreate if this entry is still the registered one for the identifier.
      guard let current = entries[identifier], current === entry else { return nil }
      return entries.removeValue(forKey: identifier)
    }
    guard let old else { return }
    IOHIDUserDeviceCancel(old.device)

    do {
      _ = try getEntry(for: identifier)
      registryLock.withLock { recomputeStatusLocked() }
      print("[UserSpaceOutputDispatcher] Recreated IOHIDUserDevice after error for \(identifier)")
    } catch {
      status = "error: \(error)"
    }
  }

  private func getEntry(for identifier: DeviceIdentifier) throws -> Entry {
    try registryLock.withLock {
      if let existing = entries[identifier] { return existing }
      let newEntry = try createDevice(for: identifier)
      entries[identifier] = newEntry
      if !status.hasPrefix("error:") { status = "on" }
      recomputeStatusLocked()
      return newEntry
    }
  }

  // MARK: - Event application (called inside reportLock.withLock)

  private func applyEvent(
    _ event: ControllerEvent,
    deadzone: Float,
    state: inout VirtualGamepadState
  ) {
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
      state.buttons =
        (state.buttons & ~dpadMask) | GamepadHIDDescriptor.dpadButtonBits(for: state.hat)
    }
  }

  private func xboxGuideReport(for event: ControllerEvent) -> [UInt8]? {
    switch event {
    case .buttonPressed(let button) where button == .guide || button == .ps:
      return [0x02, 0x01]
    case .buttonReleased(let button) where button == .guide || button == .ps:
      return [0x02, 0x00]
    default:
      return nil
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
    case .back: return 9
    case .guide, .ps: return emitsXboxGuideReport ? nil : 10
    case .dpadUp: return 11
    case .dpadDown: return 12
    case .dpadLeft: return 13
    case .dpadRight: return 14
    case .share: return 15
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

extension UserSpaceOutputDispatcher: ControllerLifecycleListener {
  // swiftlint:disable:next async_without_await
  public func controllerDidStop(_ identifier: DeviceIdentifier) async {
    let old = registryLock.withLock { entries.removeValue(forKey: identifier) }
    if let old {
      IOHIDUserDeviceCancel(old.device)
    }
    registryLock.withLock { recomputeStatusLocked() }
  }
}
