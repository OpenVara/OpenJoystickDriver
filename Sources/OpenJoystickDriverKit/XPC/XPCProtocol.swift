import Foundation

/// Mach service name shared by the daemon and any client (GUI or CLI).
/// Both sides must use the same name to establish a connection.
public let xpcServiceName = "com.openjoystickdriver.xpc"

/// The contract between the daemon process and its clients (GUI app, CLI).
///
/// XPC (cross-process communication) lets the GUI and CLI talk to the daemon
/// without running in the same process. NSXPCConnection requires an Objective-C
/// compatible protocol, so all complex types are JSON-encoded as `Data`.
@objc public protocol OpenJoystickDriverXPCProtocol: AnyObject {
  /// Lists all connected controllers.
  /// Replies with an array of human-readable device description strings.
  func listDevices(reply: @escaping ([String]) -> Void)

  /// Queries the daemon for its current status.
  /// Replies with JSON-encoded ``XPCStatusPayload`` containing permission states
  /// and connected device descriptions.
  func getStatus(reply: @escaping (Data) -> Void)

  /// Lists active profiles for all devices.
  /// Replies with a JSON-encoded array of ``Profile``.
  func listProfiles(reply: @escaping (Data) -> Void)

  /// Gets the active profile for one device.
  /// Replies with a JSON-encoded ``Profile``, or empty data if none exists.
  func getProfile(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void)

  /// Saves a profile to disk. Replies with true on success, false on failure.
  func saveProfile(profileData: Data, reply: @escaping (Bool) -> Void)

  /// Deletes the saved profile for a device and reverts to defaults.
  /// Replies with true on success.
  func resetProfile(vendorID: Int, productID: Int, reply: @escaping (Bool) -> Void)

  /// Gets every profile in the library for a device (active and inactive).
  /// Replies with a JSON-encoded array of ``Profile``.
  func allProfiles(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void)

  /// Adds a new profile to the device library.
  /// Replies with the JSON-encoded saved ``Profile`` on success, or nil on failure.
  func addProfile(
    profileData: Data,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Data?) -> Void
  )

  /// Removes a profile from the library by its UUID string.
  /// Replies with true on success. Fails if deleting the last remaining profile.
  func deleteProfile(
    profileId: String,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Bool) -> Void
  )

  /// Makes a profile the active one for its device.
  /// Replies with true on success, false if the profile was not found.
  func setActiveProfile(
    profileId: String,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Bool) -> Void
  )

  /// Gets the latest input state (buttons, sticks, triggers) for a device.
  /// Replies with JSON-encoded ``DeviceInputState``, or nil if no input has been received yet.
  @objc func getDeviceInputState(vendorID: Int, productID: Int, reply: @escaping (Data?) -> Void)

  /// Gets recent raw packets sent to or received from a device.
  /// Replies with a JSON-encoded array of ``PacketLogEntry``.
  @objc func getPacketLog(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void)

  /// Enables or disables keyboard/mouse output from button mappings.
  /// Pass true to suppress output (useful during developer packet capture).
  /// Replies with true to confirm the change.
  @objc func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void)
}

/// Status snapshot returned by ``OpenJoystickDriverXPCProtocol/getStatus(reply:)``.
///
/// Contains the current macOS permission states (as human-readable strings like
/// "granted" or "denied") and descriptions of all connected controllers.
public struct XPCStatusPayload: Codable, Sendable {
  /// Input Monitoring permission state (e.g. "granted", "denied").
  public let inputMonitoring: String
  /// Accessibility permission state (e.g. "granted", "denied").
  public let accessibility: String
  /// Human-readable descriptions of all connected controllers.
  public let connectedDevices: [String]

  public init(inputMonitoring: String, accessibility: String, connectedDevices: [String]) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
    self.connectedDevices = connectedDevices
  }
}
