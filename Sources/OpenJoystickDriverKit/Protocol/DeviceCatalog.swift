import Foundation

/// Loads and caches VID:PID -> parser name mapping
/// from bundled devices.json resource.
struct DeviceCatalog: Sendable {
  /// Maps "VID:PID" strings to parser names (e.g. "GIP", "DS4").
  let entries: [String: String]

  init() {
    if let data = Self.loadJSON(),
      let decoded = try? JSONDecoder().decode(DeviceList.self, from: data)
    {
      var map: [String: String] = [:]
      for entry in decoded.devices { map["\(entry.vendor_id):\(entry.product_id)"] = entry.parser }
      entries = map
    } else {
      print("[DeviceCatalog] Could not load devices.json - using built-in fallbacks")
      entries = ["13623:4112": "GIP", "1356:1476": "DS4", "1356:2508": "DS4"]
    }
  }

  func parserName(for identifier: DeviceIdentifier) -> String {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return entries[key] ?? "GenericHID"
  }

  private static func loadJSON() -> Data? {
    Bundle.module.url(forResource: "devices", withExtension: "json").flatMap {
      try? Data(contentsOf: $0)
    }
  }

  // MARK: - Internal JSON shape

  private struct DeviceEntry: Decodable {
    let vendor_id: Int
    let product_id: Int
    let parser: String
  }

  private struct DeviceList: Decodable { let devices: [DeviceEntry] }
}
