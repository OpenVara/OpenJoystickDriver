/// Defines the virtual HID device identity presented to the OS.
///
/// All input protocols normalize to XInputHID layout; the profile
/// only controls how the virtual device identifies itself to consumers.
public struct VirtualDeviceProfile: Sendable {
  public let vendorID: Int
  public let productID: Int
  public let productName: String
  public let manufacturer: String

  /// OpenJoystickDriver virtual gamepad — a standard HID GamePad identity that
  /// avoids triggering device-specific HID parsers in consumers (e.g. SDL's Xbox path).
  public static let openJoystickDriver = VirtualDeviceProfile(
    vendorID: 0x4F4A,  // "OJ"
    productID: 0x4447,  // "DG" (arbitrary, stable)
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  /// Xbox One S — standard for XInput/GIP controllers and the default
  /// normalization target for all protocols.
  public static let xboxOneS = VirtualDeviceProfile(
    vendorID: 0x045E,
    productID: 0x02EA,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft"
  )

  /// Default profile used when no protocol-specific profile is configured.
  /// Uses the OpenJoystickDriver virtual identity (generic HID GamePad).
  ///
  /// IMPORTANT: Do not default to spoofing a real controller's VID/PID unless
  /// the report descriptor and report bytes exactly match that controller's HID
  /// protocol. Many consumers (notably SDL) switch parsing logic based on VID/PID
  /// and will ignore inputs if the descriptor doesn't match their expectations.
  public static let `default` = openJoystickDriver
}
