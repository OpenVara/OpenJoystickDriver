/// Defines the virtual HID device identity presented to the OS.
///
/// All input protocols normalize to XInputHID layout; the profile
/// only controls how the virtual device identifies itself to consumers.
public struct VirtualDeviceProfile: Equatable, Sendable {
  public let vendorID: Int
  public let productID: Int
  /// Value used for `kIOHIDVersionNumberKey` / SDL "product version".
  ///
  /// SDL includes this 16-bit value in the GUID it uses to look up controller mappings.
  /// For some apps (PCSX2/SDL on macOS), having the expected version is required for
  /// automatic mapping to be applied.
  public let versionNumber: Int
  public let productName: String
  public let manufacturer: String

  /// OpenJoystickDriver virtual gamepad — a standard HID GamePad identity that
  /// avoids triggering device-specific HID parsers in consumers (e.g. SDL's Xbox path).
  public static let openJoystickDriver = VirtualDeviceProfile(
    vendorID: 0x4F4A,  // "OJ"
    productID: 0x4447,  // "DG" (arbitrary, stable)
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  public static let openJoystickDriverSDLMacOS = VirtualDeviceProfile(
    vendorID: 0x4F4A,
    productID: 0x4448,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  public static let openJoystickDriverGenericHID = VirtualDeviceProfile(
    vendorID: 0x4F4A,
    productID: 0x4449,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Generic HID Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  /// Xbox One S — standard for XInput/GIP controllers and the default
  /// normalization target for all protocols.
  public static let xboxOneS = VirtualDeviceProfile(
    vendorID: 0x045E,
    productID: 0x02EA,
    // Important: SDL mapping DB entry for macOS expects version=0x0000 for GUID
    // `030000005e040000ea02000000000000` (Xbox One Controller, platform: Mac OS X).
    // Matching this makes SDL treat the device as a Gamepad with automatic mappings.
    versionNumber: 0x0000,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft"
  )

  /// Xbox 360 Controller (Wired) — experimental on macOS.
  ///
  /// Note: many macOS stacks do not treat 045E:028E as a standard HID gamepad.
  public static let xbox360Wired = VirtualDeviceProfile(
    vendorID: 0x045E,
    productID: 0x028E,
    versionNumber: 0x0000,
    productName: "Xbox 360 Wired Controller",
    manufacturer: "Microsoft"
  )

  /// SDL macOS compatibility identity.
  ///
  /// This profile is intentionally not exposed in the Compatibility UI. macOS GameController
  /// claims SDL-known third-party controller identities before SDL's IOKit backend can use
  /// them, so the generic OpenJoystickDriver user-space identity is the consumer-facing
  /// SDL/PCSX2 path.
  public static let sdlMacGamepad = VirtualDeviceProfile(
    vendorID: 0x1BAD,
    productID: 0xF901,
    versionNumber: 0x0000,
    productName: "Gamestop BB070 X360 Controller",
    manufacturer: "GameStop"
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
