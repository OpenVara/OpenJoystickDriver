import Foundation

/// A snapshot of the current input state for one controller.
///
/// Updated by ``DevicePipeline`` every time a new input report arrives.
/// Used by the Developer tab to display live button, stick, and trigger values.
public struct DeviceInputState: Codable, Sendable, Equatable {
  /// USB vendor ID of the device this state belongs to.
  public let vendorID: UInt16
  /// USB product ID of the device this state belongs to.
  public let productID: UInt16
  /// Names of buttons currently held down (e.g. `["A", "LB"]`).
  public var pressedButtons: [String]
  /// Left stick horizontal axis, normalized to -1...1.
  public var leftStickX: Float
  /// Left stick vertical axis, normalized to -1...1.
  public var leftStickY: Float
  /// Right stick horizontal axis, normalized to -1...1.
  public var rightStickX: Float
  /// Right stick vertical axis, normalized to -1...1.
  public var rightStickY: Float
  /// Left trigger pressure, normalized to 0...1.
  public var leftTrigger: Float
  /// Right trigger pressure, normalized to 0...1.
  public var rightTrigger: Float

  /// Creates a zeroed-out input state for the given device.
  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
    pressedButtons = []
    leftStickX = 0
    leftStickY = 0
    rightStickX = 0
    rightStickY = 0
    leftTrigger = 0
    rightTrigger = 0
  }
}
