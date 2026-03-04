import Foundation

/// Persists and retrieves per-device profiles from
/// ~/Library/Application Support/OpenJoystickDriver/profiles/
public actor ProfileStore {
  private let directory: URL
  private var cache: [String: Profile] = [:]

  public init(directory: URL? = nil) {
    let dir = directory ?? Self.defaultDirectory()
    self.directory = dir
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch
    { debugPrint("[ProfileStore] Failed to create" + " directory: \(error)") }
  }

  /// Load profile for device. Returns cached/saved profile or generated default.
  public func profile(for identifier: DeviceIdentifier) -> Profile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    if let cached = cache[key] { return cached }
    let url = profileURL(for: identifier)
    if let data = try? Data(contentsOf: url),
      let stored = try? JSONDecoder().decode(Profile.self, from: data)
    {
      cache[key] = stored
      return stored
    }
    return Profile.makeDefault(for: identifier)
  }

  /// Persist profile to disk and update cache.
  public func save(_ profile: Profile) throws {
    let identifier = DeviceIdentifier(vendorID: profile.vendorID, productID: profile.productID)
    let key = "\(profile.vendorID):\(profile.productID)"
    let data = try JSONEncoder().encode(profile)
    let url = profileURL(for: identifier)
    try data.write(to: url, options: .atomic)
    cache[key] = profile
    debugPrint("[ProfileStore] Saved profile '\(profile.name)'" + " for \(key)")
  }

  /// List all stored profiles from disk.
  public func listProfiles() -> [Profile] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }) ?? []
    return urls.compactMap { try? JSONDecoder().decode(Profile.self, from: Data(contentsOf: $0)) }
  }

  /// Delete stored profile; future loads return default.
  public func reset(for identifier: DeviceIdentifier) throws {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    cache.removeValue(forKey: key)
    let url = profileURL(for: identifier)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func defaultDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("OpenJoystickDriver").appendingPathComponent("profiles")
  }

  private func profileURL(for identifier: DeviceIdentifier) -> URL {
    directory.appendingPathComponent("\(identifier.vendorID)-\(identifier.productID).json")
  }
}
