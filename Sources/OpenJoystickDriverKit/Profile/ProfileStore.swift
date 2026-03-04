import Foundation

/// Reads and writes per-device mapping profiles on disk.
///
/// Profiles are stored as JSON files inside
/// `~/Library/Application Support/OpenJoystickDriver/profiles/`.
/// Each device has a single-profile file (`{VID}-{PID}.json`) for the active
/// profile, and an optional library file (`{VID}-{PID}-library.json`) that
/// holds all saved profiles. The store caches the active profile in memory
/// so repeated reads do not hit disk.
public actor ProfileStore {
  private let directory: URL
  private var cache: [String: Profile] = [:]

  /// On-disk container that groups every profile for one device.
  private struct ProfileLibrary: Codable {
    var profiles: [Profile]
    var activeID: UUID
  }

  /// Creates a store that reads and writes profiles in `directory`.
  /// Pass `nil` to use the default location:
  /// `~/Library/Application Support/OpenJoystickDriver/profiles/`.
  public init(directory: URL? = nil) {
    let dir = directory ?? Self.defaultDirectory()
    self.directory = dir
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch
    { print("[ProfileStore] Failed to create directory: \(error)") }
  }

  /// Returns the active profile for a device.
  ///
  /// Checks the in-memory cache first, then disk. If no saved profile exists,
  /// a default profile is generated from ``DefaultMapping``.
  public func profile(for identifier: DeviceIdentifier) -> Profile {
    let key = cacheKey(for: identifier)
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

  /// Writes a profile to disk and updates the in-memory cache.
  ///
  /// If a library file already exists for the device, the profile is also
  /// updated (or appended) inside the library.
  public func save(_ profile: Profile) throws {
    let identifier = DeviceIdentifier(vendorID: profile.vendorID, productID: profile.productID)
    let key = cacheKey(for: identifier)
    let data = try JSONEncoder().encode(profile)
    let url = profileURL(for: identifier)
    try data.write(to: url, options: .atomic)
    cache[key] = profile
    print("[ProfileStore] Saved profile '\(profile.name)' for \(key)")

    let libURL = libraryURL(for: identifier)
    if FileManager.default.fileExists(atPath: libURL.path),
      var library = try? JSONDecoder().decode(ProfileLibrary.self, from: Data(contentsOf: libURL))
    {
      if let idx = library.profiles.firstIndex(where: { $0.id == profile.id }) {
        library.profiles[idx] = profile
      } else {
        library.profiles.append(profile)
      }
      if let libData = try? JSONEncoder().encode(library) {
        try libData.write(to: libURL, options: .atomic)
      }
    }
  }

  /// Returns every single-file profile saved in the profiles directory.
  ///
  /// Library files (`*-library.json`) are excluded. Returns an empty array
  /// when no profiles have been saved yet.
  public func listProfiles() -> [Profile] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix("-library.json") })
      ?? []
    return urls.compactMap { try? JSONDecoder().decode(Profile.self, from: Data(contentsOf: $0)) }
  }

  /// Deletes the active profile file and clears the cache for a device.
  ///
  /// After a reset, the next call to ``profile(for:)`` returns a fresh default.
  public func reset(for identifier: DeviceIdentifier) throws {
    let key = cacheKey(for: identifier)
    cache.removeValue(forKey: key)
    let url = profileURL(for: identifier)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Multi-profile library

  /// Returns every profile saved for a device, including the active one.
  ///
  /// If no library file exists yet, the current single-file profile is
  /// migrated into a new library automatically.
  public func allProfiles(for identifier: DeviceIdentifier) -> [Profile] {
    let libURL = libraryURL(for: identifier)
    if FileManager.default.fileExists(atPath: libURL.path),
      let data = try? Data(contentsOf: libURL),
      let library = try? JSONDecoder().decode(ProfileLibrary.self, from: data)
    {
      return library.profiles
    }

    let activeProfile = profile(for: identifier)
    let library = ProfileLibrary(profiles: [activeProfile], activeID: activeProfile.id)
    if let data = try? JSONEncoder().encode(library) {
      try? data.write(to: libURL, options: .atomic)
    }
    return library.profiles
  }

  /// Appends a new profile to the device library without activating it.
  public func addProfile(_ profile: Profile) throws {
    let identifier = DeviceIdentifier(vendorID: profile.vendorID, productID: profile.productID)
    let libURL = libraryURL(for: identifier)
    var library = loadOrCreateLibrary(for: identifier)
    library.profiles.append(profile)
    let data = try JSONEncoder().encode(library)
    try data.write(to: libURL, options: .atomic)
  }

  /// Removes a profile from the device library.
  ///
  /// Throws ``ProfileStoreError/cannotDeleteLastProfile`` when only one profile
  /// remains. If the deleted profile was active, the first remaining profile
  /// becomes active automatically.
  public func deleteProfile(id: UUID, for identifier: DeviceIdentifier) throws {
    let libURL = libraryURL(for: identifier)
    var library = loadOrCreateLibrary(for: identifier)
    guard library.profiles.count > 1 else { throw ProfileStoreError.cannotDeleteLastProfile }
    library.profiles.removeAll { $0.id == id }
    if library.activeID == id, let first = library.profiles.first {
      try updateActiveProfileAfterDeletion(first: first, for: identifier, library: &library)
    }
    let data = try JSONEncoder().encode(library)
    try data.write(to: libURL, options: .atomic)
  }

  /// Makes a profile the active one for its device.
  ///
  /// The profile is written to `{VID}-{PID}.json` and the library's
  /// `activeID` is updated. Throws ``ProfileStoreError/profileNotFound``
  /// when no profile with the given `id` exists in the library.
  public func setActiveProfile(id: UUID, for identifier: DeviceIdentifier) throws {
    let libURL = libraryURL(for: identifier)
    var library = loadOrCreateLibrary(for: identifier)
    guard let target = library.profiles.first(where: { $0.id == id }) else {
      throw ProfileStoreError.profileNotFound
    }
    library.activeID = id
    let key = cacheKey(for: identifier)
    cache[key] = target
    let activeData = try JSONEncoder().encode(target)
    try activeData.write(to: profileURL(for: identifier), options: .atomic)
    let libData = try JSONEncoder().encode(library)
    try libData.write(to: libURL, options: .atomic)
  }

  // MARK: - Private helpers

  private static func defaultDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("OpenJoystickDriver").appendingPathComponent("profiles")
  }

  private func updateActiveProfileAfterDeletion(
    first: Profile,
    for identifier: DeviceIdentifier,
    library: inout ProfileLibrary
  ) throws {
    library.activeID = first.id
    let key = cacheKey(for: identifier)
    cache[key] = first
    if let activeData = try? JSONEncoder().encode(first) {
      try activeData.write(to: profileURL(for: identifier), options: .atomic)
    }
  }

  private func profileURL(for identifier: DeviceIdentifier) -> URL {
    directory.appendingPathComponent("\(identifier.vendorID)-\(identifier.productID).json")
  }

  private func libraryURL(for identifier: DeviceIdentifier) -> URL {
    directory.appendingPathComponent("\(identifier.vendorID)-\(identifier.productID)-library.json")
  }

  private func cacheKey(for identifier: DeviceIdentifier) -> String {
    "\(identifier.vendorID):\(identifier.productID)"
  }

  private func loadOrCreateLibrary(for identifier: DeviceIdentifier) -> ProfileLibrary {
    let libURL = libraryURL(for: identifier)
    if FileManager.default.fileExists(atPath: libURL.path),
      let data = try? Data(contentsOf: libURL),
      let library = try? JSONDecoder().decode(ProfileLibrary.self, from: data)
    {
      return library
    }
    let active = profile(for: identifier)
    return ProfileLibrary(profiles: [active], activeID: active.id)
  }
}

/// Errors thrown by ``ProfileStore`` when a profile operation is not allowed.
public enum ProfileStoreError: Error, Sendable {
  /// The caller tried to delete the only remaining profile for a device.
  case cannotDeleteLastProfile
  /// No profile with the requested UUID exists in the device library.
  case profileNotFound
}
