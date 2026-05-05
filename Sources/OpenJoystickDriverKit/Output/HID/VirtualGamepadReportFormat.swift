import Foundation

/// Normalized virtual gamepad state used by all output backends.
public struct VirtualGamepadState: Sendable {
  public var buttons: UInt32
  public var leftStickX: Int16
  public var leftStickY: Int16
  public var rightStickX: Int16
  public var rightStickY: Int16
  public var leftTrigger: Int16
  public var rightTrigger: Int16
  public var hat: GamepadHIDDescriptor.Hat

  public init(
    buttons: UInt32 = 0,
    leftStickX: Int16 = 0,
    leftStickY: Int16 = 0,
    rightStickX: Int16 = 0,
    rightStickY: Int16 = 0,
    leftTrigger: Int16 = 0,
    rightTrigger: Int16 = 0,
    hat: GamepadHIDDescriptor.Hat = .neutral
  ) {
    self.buttons = buttons
    self.leftStickX = leftStickX
    self.leftStickY = leftStickY
    self.rightStickX = rightStickX
    self.rightStickY = rightStickY
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.hat = hat
  }
}

/// Report format for a virtual HID gamepad: descriptor + report bytes builder.
public protocol VirtualGamepadReportFormat: Sendable {
  /// HID report descriptor bytes.
  var descriptor: [UInt8] { get }

  /// Size of one input report *payload* (does not include the optional Report ID byte).
  var inputReportPayloadSize: Int { get }

  /// HID Report ID used for the input report, or nil if the descriptor does not use report IDs.
  var inputReportID: UInt8? { get }

  /// Builds one complete input report.
  ///
  /// If `inputReportID` is non-nil, the returned bytes MUST begin with that Report ID byte.
  func buildInputReport(from state: VirtualGamepadState) -> [UInt8]
}

/// Generic OJD HID GamePad format (matches ``GamepadHIDDescriptor``).
public struct OJDGenericGamepadFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = GamepadHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = GamepadHIDDescriptor.reportSize
  public let inputReportID: UInt8? = nil
  private let includesDpadButtonBits: Bool

  public init(includesDpadButtonBits: Bool = true) {
    self.includesDpadButtonBits = includesDpadButtonBits
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: GamepadHIDDescriptor.reportSize)
    let dpadMask: UInt32 = 0xF << 11
    let buttons = includesDpadButtonBits ? state.buttons : (state.buttons & ~dpadMask)
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0xFF)
    let lsxB = state.leftStickX.littleEndianBytes
    r[2] = lsxB.0
    r[3] = lsxB.1
    let lsyB = state.leftStickY.littleEndianBytes
    r[4] = lsyB.0
    r[5] = lsyB.1
    let ltB = state.leftTrigger.littleEndianBytes
    r[6] = ltB.0
    r[7] = ltB.1
    let rsxB = state.rightStickX.littleEndianBytes
    r[8] = rsxB.0
    r[9] = rsxB.1
    let rsyB = state.rightStickY.littleEndianBytes
    r[10] = rsyB.0
    r[11] = rsyB.1
    let rtB = state.rightTrigger.littleEndianBytes
    r[12] = rtB.0
    r[13] = rtB.1
    r[14] = state.hat.rawValue & 0x0F
    return r
  }
}

