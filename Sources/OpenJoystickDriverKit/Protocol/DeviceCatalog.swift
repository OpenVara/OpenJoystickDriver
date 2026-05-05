import Foundation

/// Per-device USB configuration resolved from devices.json.
public struct USBEndpointConfig: Sendable {
  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool

  public static let gipDefault = USBEndpointConfig(
    inputEndpoint: 0x82, outputEndpoint: 0x02, needsSetConfiguration: false)
}

/// Loads and caches VID:PID -> parser name mapping
/// from bundled devices.json resource.
struct DeviceCatalog: Sendable {
  /// Maps "VID:PID" strings to parser names (e.g. "GIP", "DS4").
  let entries: [String: String]

  /// Maps "VID:PID" strings to virtual profile keys (e.g. "xboxOneS").
  let profileEntries: [String: String]

  /// Maps "VID:PID" strings to per-device endpoint overrides.
  let endpointEntries: [String: USBEndpointConfig]

  init() {
    if let data = Self.loadJSON(),
      let decoded = try? JSONDecoder().decode(DeviceList.self, from: data)
    {
      var map: [String: String] = [:]
      var profiles: [String: String] = [:]
      var endpoints: [String: USBEndpointConfig] = [:]
      for entry in decoded.devices {
        let key = "\(entry.vendorId):\(entry.productId)"
        map[key] = entry.parser
        if let vp = entry.virtualProfile { profiles[key] = vp }
        if let inEP = entry.inputEndpoint, let outEP = entry.outputEndpoint {
          endpoints[key] = USBEndpointConfig(
            inputEndpoint: UInt8(inEP), outputEndpoint: UInt8(outEP),
            needsSetConfiguration: entry.needsSetConfiguration ?? false)
        }
      }
      entries = map
      profileEntries = profiles
      endpointEntries = endpoints
    } else {
      print("[DeviceCatalog] Could not load devices.json - using built-in fallbacks")
      entries = ["13623:4112": "GIP", "1356:1476": "DS4", "1356:2508": "DS4"]
      profileEntries = [:]
      endpointEntries = [:]
    }
  }

  func parserName(for identifier: DeviceIdentifier) -> String {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return entries[key] ?? "GenericHID"
  }

  /// Returns the virtual device profile for a physical device.
  ///
  /// Looks up the `virtual_profile` field from devices.json by VID:PID.
  /// Falls back to `.default` (Xbox One S) for unknown devices.
  func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    guard let profileKey = profileEntries[key] else { return .default }
    switch profileKey {
    case "xboxOneS": return .xboxOneS
    default: return .default
    }
  }

  /// Returns USB endpoint config for a device, falling back to GIP defaults.
  func endpointConfig(for identifier: DeviceIdentifier) -> USBEndpointConfig {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return endpointEntries[key] ?? .gipDefault
  }

  private static func loadJSON() -> Data? {
    Bundle.module.url(forResource: "devices", withExtension: "json").flatMap {
      try? Data(contentsOf: $0)
    }
  }

  // MARK: - Internal JSON shape

  private struct DeviceEntry: Decodable {
    let vendorId: Int
    let productId: Int
    let parser: String
    let virtualProfile: String?
    let inputEndpoint: Int?
    let outputEndpoint: Int?
    let needsSetConfiguration: Bool?

    enum CodingKeys: String, CodingKey {
      case vendorId = "vendor_id"
      case productId = "product_id"
      case parser
      case virtualProfile = "virtual_profile"
      case inputEndpoint = "input_endpoint"
      case outputEndpoint = "output_endpoint"
      case needsSetConfiguration = "needs_set_configuration"
    }
  }

  private struct DeviceList: Decodable { let devices: [DeviceEntry] }
}
