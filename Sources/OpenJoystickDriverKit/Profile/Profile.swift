import CoreGraphics
import Foundation

/// A button and axis mapping profile for a single device.
///
/// Each profile is stored as JSON in
/// `~/Library/Application Support/OpenJoystickDriver/profiles/`.
/// A device can have multiple profiles; the active one is used for output dispatch.
public struct Profile: Codable, Sendable {
  /// Unique identifier for this profile. Generated automatically for new profiles.
  public var id: UUID
  /// Human-readable name shown in the profile picker (e.g. "Racing", "Default").
  public var name: String
  /// USB vendor ID of the device this profile belongs to.
  public var vendorID: UInt16
  /// USB product ID of the device this profile belongs to.
  public var productID: UInt16
  /// Maps each button name (`Button.rawValue`) to a macOS key code (`CGKeyCode`).
  public var buttonMappings: [String: UInt16]
  /// Minimum stick deflection (0...1) before movement is registered.
  public var stickDeadzone: Float
  /// Multiplier applied to stick input when moving the mouse cursor.
  public var stickMouseSensitivity: Float
  /// Multiplier applied to right-stick input when scrolling.
  public var stickScrollSensitivity: Float

  public init(
    id: UUID = UUID(),
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    buttonMappings: [String: UInt16],
    stickDeadzone: Float,
    stickMouseSensitivity: Float,
    stickScrollSensitivity: Float
  ) {
    self.id = id
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.buttonMappings = buttonMappings
    self.stickDeadzone = stickDeadzone
    self.stickMouseSensitivity = stickMouseSensitivity
    self.stickScrollSensitivity = stickScrollSensitivity
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, vendorID, productID, buttonMappings
    case stickDeadzone, stickMouseSensitivity, stickScrollSensitivity
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    vendorID = try container.decode(UInt16.self, forKey: .vendorID)
    productID = try container.decode(UInt16.self, forKey: .productID)
    buttonMappings = try container.decode([String: UInt16].self, forKey: .buttonMappings)
    stickDeadzone = try container.decode(Float.self, forKey: .stickDeadzone)
    stickMouseSensitivity = try container.decode(Float.self, forKey: .stickMouseSensitivity)
    stickScrollSensitivity = try container.decode(Float.self, forKey: .stickScrollSensitivity)
  }

  /// Creates a new profile pre-filled with ``DefaultMapping`` values for the given device.
  ///
  /// Returns a profile named "Default" with all standard button and axis mappings.
  public static func makeDefault(for identifier: DeviceIdentifier) -> Self {
    var mappings: [String: UInt16] = [:]
    for (button, keyCode) in DefaultMapping.buttonKeyCodes { mappings[button.rawValue] = keyCode }
    return Self(
      id: UUID(),
      name: "Default",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      buttonMappings: mappings,
      stickDeadzone: DefaultMapping.stickDeadzone,
      stickMouseSensitivity: DefaultMapping.stickMouseSensitivity,
      stickScrollSensitivity: DefaultMapping.stickScrollSensitivity
    )
  }

  /// Returns the key code mapped to `button` in this profile.
  ///
  /// Falls back to ``DefaultMapping`` when the profile has no explicit mapping.
  public func keyCode(for button: Button) -> CGKeyCode? {
    if let code = buttonMappings[button.rawValue] { return CGKeyCode(code) }
    return DefaultMapping.buttonKeyCodes[button]
  }
}
