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

extension XPCError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Not connected to daemon."
    case .timeout: return "Daemon did not respond (timeout)."
    case .invalidResponse: return "Invalid response from daemon (version mismatch?)."
    }
  }
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
///
/// - Important: Thread-safe only when accessed from a single isolation domain (e.g. `@MainActor`).
public final class XPCClient: @unchecked Sendable {
  private var connection: NSXPCConnection?

  /// Creates a new XPCClient.
  public init() {}

  /// Opens a connection to the daemon's Mach service.
  ///
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

  /// True while a connection exists.
  ///
  /// Does not guarantee the daemon is still alive.
  public var isConnected: Bool { connection != nil }

  // MARK: - XPC Methods

  /// Returns device descriptions from daemon.
  ///
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

  /// Gets the latest input snapshot (buttons, sticks, triggers) for a device.
  ///
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

  /// Gets recent raw USB packets exchanged with a device.
  ///
  /// Useful for debugging protocols.
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
  ///
  /// Pass true to suppress output during developer packet capture.
  public func setSuppressOutput(_ suppress: Bool) async throws {
    let _: Bool = try await xpcCall { service, reply in
      service.setSuppressOutput(suppress, reply: reply)
    }
  }

  /// Enables/disables the user-space virtual gamepad (IOHIDUserDevice).
  public func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool) async throws {
    let _: Bool = try await xpcCall { service, reply in
      service.setUserSpaceVirtualDeviceEnabled(enabled, reply: reply)
    }
  }

  /// Sets the daemon virtual device mode.
  ///
  /// Values: "driverKit", "compatUserSpace", or "both".
  public func setVirtualDeviceMode(_ mode: String) async throws {
    let _: Bool = try await xpcCall { service, reply in
      service.setVirtualDeviceMode(mode, reply: reply)
    }
  }

  /// Returns the daemon virtual device mode.
  public func getVirtualDeviceMode() async throws -> String {
    try await xpcCall { service, reply in service.getVirtualDeviceMode(reply: reply) }
  }

  /// Returns whether the user-space virtual gamepad is enabled.
  public func getUserSpaceVirtualDeviceEnabled() async throws -> Bool {
    try await xpcCall { service, reply in service.getUserSpaceVirtualDeviceEnabled(reply: reply) }
  }

  /// Returns a short status string for the user-space virtual gamepad.
  public func getUserSpaceVirtualDeviceStatus() async throws -> String {
    try await xpcCall { service, reply in service.getUserSpaceVirtualDeviceStatus(reply: reply) }
  }

  /// Returns a diagnostics snapshot of HID gamepad devices as seen by IOKit.
  public func getVirtualDeviceDiagnostics() async throws -> XPCVirtualDeviceDiagnosticsPayload {
    let data: Data = try await xpcCall { service, reply in
      service.getVirtualDeviceDiagnostics(reply: reply)
    }
    guard let payload = try? JSONDecoder().decode(XPCVirtualDeviceDiagnosticsPayload.self, from: data)
    else {
      throw XPCError.invalidResponse
    }
    return payload
  }

  /// Sets the daemon output routing mode.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  public func setOutputMode(_ mode: String) async throws {
    let _: Bool = try await xpcCall { service, reply in
      service.setOutputMode(mode, reply: reply)
    }
  }

  /// Gets the daemon output routing mode.
  public func getOutputMode() async throws -> String {
    try await xpcCall { service, reply in service.getOutputMode(reply: reply) }
  }

  /// Runs a short virtual device self-test.
  public func runVirtualDeviceSelfTest(seconds: Int) async throws -> XPCVirtualDeviceSelfTestPayload
  {
    let data: Data = try await xpcCall { service, reply in
      service.runVirtualDeviceSelfTest(seconds: seconds, reply: reply)
    }
    guard let payload = try? JSONDecoder().decode(XPCVirtualDeviceSelfTestPayload.self, from: data)
    else {
      throw XPCError.invalidResponse
    }
    return payload
  }

  // MARK: - Private

  /// Wraps an XPC reply-block call as a Swift async function.
  private func xpcCall<T: Sendable>(
    _ body: @escaping (any OpenJoystickDriverXPCProtocol, @escaping (T) -> Void) -> Void
  ) async throws -> T {
    guard let conn = connection else { throw XPCError.notConnected }
    return try await withCheckedThrowingContinuation { cont in
      let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
        // Ensure subsequent calls reconnect cleanly instead of staying on a poisoned connection.
        self?.disconnect()
        cont.resume(throwing: error)
      }
      guard let service = proxy as? any OpenJoystickDriverXPCProtocol else {
        cont.resume(throwing: XPCError.invalidResponse)
        return
      }
      body(service) { value in cont.resume(returning: value) }
    }
  }
}
