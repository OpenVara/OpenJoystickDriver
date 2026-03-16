import Foundation

/// How a stick's deflection is translated into output events.
public enum StickMode: String, Codable, Sendable {
  /// Moves the mouse cursor at a speed proportional to stick deflection (velocity model).
  case mouse
  /// Positions the cursor within a fixed-radius region: deflection = offset from center.
  /// The center is captured when the stick first leaves the deadzone and restored on neutral.
  /// Use this for racing games / steering where position = angle.
  case mouseRegion
  /// Scrolls (right-stick default).
  case scroll
  /// Emits key presses based on direction.
  case keyboard
}

/// A button and axis mapping profile for a single device.
///
/// Each profile is stored as JSON in
/// `~/Library/Application Support/OpenJoystickDriver/profiles/`.
/// A device can have multiple profiles; the active one is used for output dispatch.
public struct Profile: Codable, Sendable {
  /// Unique identifier for this profile.
  ///
  /// Generated automatically for new profiles.
  public var id: UUID
  /// Human-readable name shown in the profile picker (e.g. "Racing", "Default").
  public var name: String
  /// USB vendor ID of the device this profile belongs to.
  public var vendorID: UInt16
  /// USB product ID of the device this profile belongs to.
  public var productID: UInt16
  /// Maps each button name (``Button/rawValue``) to a virtual HID button index (1-based).
  ///
  /// Empty by default; reserved for future per-device button remapping.
  public var buttonMappings: [String: UInt16]
  /// Minimum stick deflection (0...1) before movement is registered.
  public var stickDeadzone: Float
  /// Multiplier applied to stick input when moving the mouse cursor.
  public var stickMouseSensitivity: Float
  /// Multiplier applied to right-stick input when scrolling.
  public var stickScrollSensitivity: Float
  /// Half-width of the cursor region in pixels used by the ``StickMode/mouseRegion`` mode.
  ///
  /// Full stick deflection moves the cursor exactly this many pixels from the center point.
  public var stickMouseRegionRadius: Float
  /// Output mode for the left stick.
  public var leftStickMode: StickMode
  /// Output mode for the right stick.
  public var rightStickMode: StickMode
  /// Bundle ID of the target application.
  ///
  /// Reserved for future use.
  public var targetBundleID: String?

  /// Creates a new Profile.
  public init(
    id: UUID = UUID(),
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    buttonMappings: [String: UInt16],
    stickDeadzone: Float,
    stickMouseSensitivity: Float,
    stickScrollSensitivity: Float,
    stickMouseRegionRadius: Float = 200.0,
    leftStickMode: StickMode = .mouse,
    rightStickMode: StickMode = .scroll,
    targetBundleID: String? = nil
  ) {
    self.id = id
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.buttonMappings = buttonMappings
    self.stickDeadzone = stickDeadzone
    self.stickMouseSensitivity = stickMouseSensitivity
    self.stickScrollSensitivity = stickScrollSensitivity
    self.stickMouseRegionRadius = stickMouseRegionRadius
    self.leftStickMode = leftStickMode
    self.rightStickMode = rightStickMode
    self.targetBundleID = targetBundleID
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, vendorID, productID, buttonMappings
    case stickDeadzone, stickMouseSensitivity, stickScrollSensitivity, stickMouseRegionRadius
    case leftStickMode, rightStickMode
    case targetBundleID
  }

  /// Creates a Profile by decoding from the given decoder.
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
    stickMouseRegionRadius =
      (try? container.decode(Float.self, forKey: .stickMouseRegionRadius)) ?? 200.0
    leftStickMode = (try? container.decode(StickMode.self, forKey: .leftStickMode)) ?? .mouse
    rightStickMode = (try? container.decode(StickMode.self, forKey: .rightStickMode)) ?? .scroll
    targetBundleID = try? container.decode(String.self, forKey: .targetBundleID)
  }

  /// Returns a default profile for the given device identifier.
  public static func makeDefault(for identifier: DeviceIdentifier) -> Self {
    Self(
      id: UUID(),
      name: "Default",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      buttonMappings: [:],
      stickDeadzone: 0.15,
      stickMouseSensitivity: 8.0,
      stickScrollSensitivity: 3.0,
      stickMouseRegionRadius: 200.0
    )
  }
}
