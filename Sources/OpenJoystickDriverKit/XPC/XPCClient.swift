import Foundation

public enum XPCError: Error, Sendable {
  case notConnected
  case timeout
  case invalidResponse
}

/// Connects to running daemon via NSXPCConnection.
/// Use connect() before calling any methods.
/// Falls back gracefully if daemon is not running.
public final class XPCClient: @unchecked Sendable {
  private var connection: NSXPCConnection?

  public init() {}

  public func connect() {
    let conn = NSXPCConnection(machServiceName: xpcServiceName)
    conn.remoteObjectInterface = NSXPCInterface(with: OpenJoystickDriverXPCProtocol.self)
    conn.invalidationHandler = { [weak self] in
      self?.connection = nil
      debugPrint("[XPCClient] Connection invalidated")
    }
    conn.interruptionHandler = { debugPrint("[XPCClient] Connection interrupted") }
    conn.resume()
    connection = conn
  }

  public func disconnect() {
    connection?.invalidate()
    connection = nil
  }

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

  public func listProfiles() async throws -> [Profile] {
    let data: Data = try await xpcCall { service, reply in service.listProfiles(reply: reply) }
    guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
      throw XPCError.invalidResponse
    }
    return profiles
  }

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

  public func saveProfile(_ profile: Profile) async throws {
    guard let data = try? JSONEncoder().encode(profile) else { throw XPCError.invalidResponse }
    let success: Bool = try await xpcCall { service, reply in
      service.saveProfile(profileData: data, reply: reply)
    }
    if !success { throw XPCError.invalidResponse }
  }

  public func resetProfile(vendorID: UInt16, productID: UInt16) async throws {
    let success: Bool = try await xpcCall { service, reply in
      service.resetProfile(vendorID: Int(vendorID), productID: Int(productID), reply: reply)
    }
    if !success { throw XPCError.invalidResponse }
  }

  // MARK: - Private

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
