import CoreGraphics
import Foundation

/// Per-device button remapping and axis configuration profile.
/// Stored as JSON in ~/Library/Application Support/OpenJoystickDriver/profiles/
public struct Profile: Codable, Sendable {
  public var name: String
  public var vendorID: UInt16
  public var productID: UInt16
  /// Button.rawValue (String) -> CGKeyCode (UInt16)
  public var buttonMappings: [String: UInt16]
  public var stickDeadzone: Float
  public var stickMouseSensitivity: Float
  public var stickScrollSensitivity: Float

  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    buttonMappings: [String: UInt16],
    stickDeadzone: Float,
    stickMouseSensitivity: Float,
    stickScrollSensitivity: Float
  ) {
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.buttonMappings = buttonMappings
    self.stickDeadzone = stickDeadzone
    self.stickMouseSensitivity = stickMouseSensitivity
    self.stickScrollSensitivity = stickScrollSensitivity
  }

  /// Build default profile from DefaultMapping for given device.
  public static func makeDefault(for identifier: DeviceIdentifier) -> Self {
    var mappings: [String: UInt16] = [:]
    for (button, keyCode) in DefaultMapping.buttonKeyCodes { mappings[button.rawValue] = keyCode }
    return Self(
      name: "Default",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      buttonMappings: mappings,
      stickDeadzone: DefaultMapping.stickDeadzone,
      stickMouseSensitivity: DefaultMapping.stickMouseSensitivity,
      stickScrollSensitivity: DefaultMapping.stickScrollSensitivity
    )
  }

  /// Return CGKeyCode for button: profile mapping
  /// first, then DefaultMapping fallback.
  public func keyCode(for button: Button) -> CGKeyCode? {
    if let code = buttonMappings[button.rawValue] { return CGKeyCode(code) }
    return DefaultMapping.buttonKeyCodes[button]
  }
}
