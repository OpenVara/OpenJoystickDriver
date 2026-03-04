import Foundation

/// Errors thrown by ``XPCClient`` when communication with the daemon fails.
public enum XPCError: Error, Sendable {
  /// No connection to the daemon. Call ``XPCClient/connect()`` first,
  /// or check that the daemon is running.
  case notConnected
  /// The daemon did not reply within the expected time.
  /// The daemon may have crashed or may not be installed.
  case timeout
  /// The daemon replied, but the data could not be decoded.
  /// This usually means a version mismatch between client and daemon.
  case invalidResponse
}

/// Client for talking to the OpenJoystickDriver daemon over XPC.
///
/// Typical usage:
/// 1. Create an instance: `let client = XPCClient()`
/// 2. Open the connection: `client.connect()`
/// 3. Call methods: `let devices = try await client.listDevices()`
/// 4. When finished: `client.disconnect()`
///
/// If the daemon is not running, ``connect()`` will succeed but subsequent
/// method calls will throw ``XPCError/notConnected`` once the connection is
/// invalidated by the system.
public final class XPCClient: @unchecked Sendable {
  private var connection: NSXPCConnection?

  public init() {}

  /// Opens a connection to the daemon's Mach service.
  /// Safe to call multiple times - replaces any existing connection.
  public func connect() {
    let conn = NSXPCConnection(machServiceName: xpcServiceName)
    conn.remoteObjectInterface = NSXPCInterface(with: OpenJoystickDriverXPCProtocol.self)
    conn.invalidationHandler = { [weak self] in
      self?.connection = nil
      print("[XPCClient] Connection invalidated")
    }
    conn.interruptionHandler = {}
    conn.resume()
    connection = conn
  }

  /// Closes the connection to the daemon and releases resources.
  public func disconnect() {
    connection?.invalidate()
    connection = nil
  }

  /// True while a connection exists. Does not guarantee the daemon is still alive.
  public var isConnected: Bool { connection != nil }

  // MARK: - XPC Methods

  /// Returns device descriptions from daemon.
  /// Throws XPCError.notConnected if daemon is not running.
  public func listDevices() async throws -> [String] {
    try await xpcCall { service, reply in service.listDevices(reply: reply) }
  }

  /// Returns status payload from daemon.
  public func getStatus() async throws -> XPCStatusPayload {
    let data: Data = try await xpcCall { service, reply in service.getStatus(reply: reply) }
    guard let payload = try? JSONDecoder().decode(XPCStatusPayload.self, from: data) else {
      throw XPCError.invalidResponse
    }
    return payload
  }

  /// Gets the active profile for every device that has one.
  public func listProfiles() async throws -> [Profile] {
    let data: Data = try await xpcCall { service, reply in service.listProfiles(reply: reply) }
    guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
      throw XPCError.invalidResponse
    }
    return profiles
  }

  /// Gets the active profile for a specific device. Returns nil if no profile is saved.
  public func getProfile(vendorID: UInt16, productID: UInt16) async throws -> Profile? {
    let data: Data = try await xpcCall { service, reply in
      service.getProfile(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    if data.isEmpty { return nil }
    guard let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
      throw XPCError.invalidResponse
    }
    return profile
  }

  /// Saves a profile to disk on the daemon side. Throws on failure.
  public func saveProfile(_ profile: Profile) async throws {
    guard let data = try? JSONEncoder().encode(profile) else { throw XPCError.invalidResponse }
    let success: Bool = try await xpcCall { service, reply in
      service.saveProfile(profileData: data, reply: reply)
    }
    if !success { throw XPCError.invalidResponse }
  }

  /// Deletes the saved profile for a device and reverts to default mappings.
  public func resetProfile(vendorID: UInt16, productID: UInt16) async throws {
    let success: Bool = try await xpcCall { service, reply in
      service.resetProfile(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    if !success { throw XPCError.invalidResponse }
  }

  /// Gets every profile in the library for a device (both active and inactive).
  public func allProfiles(vendorID: UInt16, productID: UInt16) async throws -> [Profile] {
    let data: Data = try await xpcCall { service, reply in
      service.allProfiles(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
      throw XPCError.invalidResponse
    }
    return profiles
  }

  /// Adds a new profile to the device library. Returns the saved profile with its assigned ID.
  public func addProfile(_ profile: Profile) async throws -> Profile {
    guard let data = try? JSONEncoder().encode(profile) else { throw XPCError.invalidResponse }
    let responseData: Data? = try await xpcCall { service, reply in
      service.addProfile(
        profileData: data,
        vendorID: Int(profile.vendorID),
        productID: Int(profile.productID),
        reply: reply
      )
    }
    guard let responseData, let saved = try? JSONDecoder().decode(Profile.self, from: responseData)
    else { throw XPCError.invalidResponse }
    return saved
  }

  /// Removes a profile from the device library. Throws if it is the last remaining profile.
  public func deleteProfile(id: UUID, vendorID: UInt16, productID: UInt16) async throws {
    let success: Bool = try await xpcCall { service, reply in
      service.deleteProfile(
        profileId: id.uuidString,
        vendorID: Int(vendorID),
        productID: Int(productID),
        reply: reply
      )
    }
    if !success { throw XPCError.invalidResponse }
  }

  /// Makes a profile the active one for its device. The previous active profile is deactivated.
  public func setActiveProfile(id: UUID, vendorID: UInt16, productID: UInt16) async throws {
    let success: Bool = try await xpcCall { service, reply in
      service.setActiveProfile(
        profileId: id.uuidString,
        vendorID: Int(vendorID),
        productID: Int(productID),
        reply: reply
      )
    }
    if !success { throw XPCError.invalidResponse }
  }

  /// Gets the latest input snapshot (buttons, sticks, triggers) for a device.
  /// Returns nil if no input has been received from the controller yet.
  public func deviceInputState(vendorID: UInt16, productID: UInt16) async throws
    -> DeviceInputState?
  {
    let data: Data? = try await xpcCall { service, reply in
      service.getDeviceInputState(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    guard let data else { return nil }
    return try? JSONDecoder().decode(DeviceInputState.self, from: data)
  }

  /// Gets recent raw USB packets exchanged with a device. Useful for debugging protocols.
  public func packetLog(vendorID: UInt16, productID: UInt16) async throws -> [PacketLogEntry] {
    let data: Data = try await xpcCall { service, reply in
      service.getPacketLog(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    guard let entries = try? JSONDecoder().decode([PacketLogEntry].self, from: data) else {
      throw XPCError.invalidResponse
    }
    return entries
  }

  /// Enables or disables keyboard/mouse output from button mappings.
  /// Pass true to suppress output during developer packet capture.
  public func setSuppressOutput(_ suppress: Bool) async throws {
    let _: Bool = try await xpcCall { service, reply in
      service.setSuppressOutput(suppress, reply: reply)
    }
  }

  // MARK: - Private

  /// Wraps an XPC reply-block call as a Swift async function.
  private func xpcCall<T: Sendable>(
    _ body: @escaping (any OpenJoystickDriverXPCProtocol, @escaping (T) -> Void) -> Void
  ) async throws -> T {
    guard let conn = connection else { throw XPCError.notConnected }
    return try await withCheckedThrowingContinuation { cont in
      let proxy = conn.remoteObjectProxyWithErrorHandler { error in cont.resume(throwing: error) }
      guard let service = proxy as? any OpenJoystickDriverXPCProtocol else {
        cont.resume(throwing: XPCError.invalidResponse)
        return
      }
      body(service) { value in cont.resume(returning: value) }
    }
  }
}
