import Foundation

/// Mach service name used by daemon and client.
public let xpcServiceName = "com.openjoystickdriver.xpc"

/// XPC protocol bridging daemon to GUI/CLI.
/// All types are ObjC-compatible for NSXPCConnection.
/// Complex types are JSON-encoded as Data.
@objc public protocol OpenJoystickDriverXPCProtocol: AnyObject {
  /// Returns array of DeviceIdentifier description strings
  /// for all currently connected controllers.
  func listDevices(reply: @escaping ([String]) -> Void)

  /// Returns JSON-encoded XPCStatusPayload.
  func getStatus(reply: @escaping (Data) -> Void)

  /// Returns JSON-encoded [Profile] array.
  func listProfiles(reply: @escaping (Data) -> Void)

  /// Returns JSON-encoded Profile? for given device.
  func getProfile(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void)

  /// Saves JSON-encoded Profile. Returns true on success.
  func saveProfile(profileData: Data, reply: @escaping (Bool) -> Void)

  /// Resets profile to default. Returns true on success.
  func resetProfile(vendorID: Int, productID: Int, reply: @escaping (Bool) -> Void)
}

/// Serializable status payload returned by getStatus.
public struct XPCStatusPayload: Codable, Sendable {
  public let inputMonitoring: String
  public let accessibility: String
  public let connectedDevices: [String]

  public init(inputMonitoring: String, accessibility: String, connectedDevices: [String]) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
    self.connectedDevices = connectedDevices
  }
}
