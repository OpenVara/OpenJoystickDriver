/// Defines the virtual HID device identity presented to the OS.
///
/// All input protocols normalize to XInputHID layout; the profile
/// only controls how the virtual device identifies itself to consumers.
public struct VirtualDeviceProfile: Sendable {
  public let vendorID: Int
  public let productID: Int
  public let productName: String
  public let manufacturer: String

  /// Xbox One S — standard for XInput/GIP controllers and the default
  /// normalization target for all protocols.
  public static let xboxOneS = VirtualDeviceProfile(
    vendorID: 0x045E,
    productID: 0x02EA,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft"
  )

  /// Default profile used when no protocol-specific profile is configured.
  /// Xbox is the universal standard that SDL, GCController, and browsers
  /// all recognize and auto-map correctly.
  public static let `default` = xboxOneS
}
