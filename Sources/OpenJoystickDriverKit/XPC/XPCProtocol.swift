import Foundation

/// Mach service name shared by the daemon and any client (GUI or CLI).
///
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

/// Structured description of a connected controller, used in ``XPCStatusPayload``.
public struct XPCDeviceDescription: Codable, Sendable {
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Name of the protocol parser in use (e.g. "GIP", "DS4").
  public let parser: String
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?

  /// Creates a new XPCDeviceDescription.
  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    parser: String,
    connection: String,
    serialNumber: String?
  ) {
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.parser = parser
    self.connection = connection
    self.serialNumber = serialNumber
  }
}

/// Status snapshot returned by ``OpenJoystickDriverXPCProtocol/getStatus(reply:)``.
///
/// Contains the current macOS permission states (as human-readable strings like
/// "granted" or "denied") and descriptions of all connected controllers.
public struct XPCStatusPayload: Codable, Sendable {
  /// Input Monitoring permission state (e.g. "granted", "denied").
  public let inputMonitoring: String
  /// Structured descriptions of all connected controllers.
  public let connectedDevices: [XPCDeviceDescription]

  /// Creates a new XPCStatusPayload.
  public init(inputMonitoring: String, connectedDevices: [XPCDeviceDescription]) {
    self.inputMonitoring = inputMonitoring
    self.connectedDevices = connectedDevices
  }
}
