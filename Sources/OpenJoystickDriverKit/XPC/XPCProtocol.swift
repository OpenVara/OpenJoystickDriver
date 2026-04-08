import Foundation

/// Mach service name shared by the daemon and any client (GUI or CLI).
///
/// Both sides must use the same name to establish a connection.
public let xpcServiceName = "com.openjoystickdriver.xpc"

/// Which virtual device output path the daemon should actively drive.
///
/// - `auto`: prefer DriverKit, fall back to user-space only if DriverKit output is unstable.
/// - `driverKit`: send reports to the DriverKit dext only.
/// - `compatUserSpace`: create an IOHIDUserDevice and send reports to it only.
/// - `both`: send reports to both (developer-only; can cause double input).
public enum VirtualDeviceMode: String, Codable, CaseIterable, Sendable {
  case auto
  case driverKit
  case compatUserSpace
  case both
}

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

  /// Sets the daemon virtual device mode.
  ///
  /// Values: "driverKit", "compatUserSpace", or "both".
  @objc func setVirtualDeviceMode(_ modeRaw: String, reply: @escaping (Bool) -> Void)

  /// Gets the daemon virtual device mode.
  ///
  /// Values: "driverKit", "compatUserSpace", or "both".
  @objc func getVirtualDeviceMode(reply: @escaping (String) -> Void)

  /// Enables/disables the user-space virtual gamepad (IOHIDUserDevice).
  ///
  /// This is a no-reboot compatibility mode for apps that ignore DriverKit
  /// virtual HID devices.
  @objc func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool, reply: @escaping (Bool) -> Void)

  /// Returns whether the user-space virtual gamepad is enabled.
  @objc func getUserSpaceVirtualDeviceEnabled(reply: @escaping (Bool) -> Void)

  /// Returns a short status string for the user-space virtual gamepad.
  @objc func getUserSpaceVirtualDeviceStatus(reply: @escaping (String) -> Void)

  /// Returns a diagnostics snapshot of HID gamepad devices as seen by IOKit.
  ///
  /// Reply is JSON-encoded ``XPCVirtualDeviceDiagnosticsPayload``.
  @objc func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void)

  /// Sets the daemon output routing mode.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  @objc func setOutputMode(_ mode: String, reply: @escaping (Bool) -> Void)

  /// Gets the daemon output routing mode.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  @objc func getOutputMode(reply: @escaping (String) -> Void)

  /// Runs a short self-test that listens for input events on OJD virtual devices.
  ///
  /// Reply is JSON-encoded ``XPCVirtualDeviceSelfTestPayload``.
  @objc func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void)
}

/// Redacted serial number state for a HID device.
public enum XPCSerialKind: String, Codable, Sendable {
  case none
  case ojdUserSpace
  case present
}

/// Safe (non-sensitive) snapshot of a HID "GamePad" device as seen by IOKit.
public struct XPCHIDGamepadSnapshot: Codable, Sendable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let product: String?
  public let transport: String?
  public let locationID: UInt32?
  public let serialKind: XPCSerialKind
  public let ioUserClass: String?

  /// True if this looks like our DriverKit virtual device.
  public let isOJDDriverKit: Bool
  /// True if this looks like our user-space IOHIDUserDevice.
  public let isOJDUserSpace: Bool

  public init(
    vendorID: UInt16,
    productID: UInt16,
    product: String?,
    transport: String?,
    locationID: UInt32?,
    serialKind: XPCSerialKind,
    ioUserClass: String?,
    isOJDDriverKit: Bool,
    isOJDUserSpace: Bool
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.transport = transport
    self.locationID = locationID
    self.serialKind = serialKind
    self.ioUserClass = ioUserClass
    self.isOJDDriverKit = isOJDDriverKit
    self.isOJDUserSpace = isOJDUserSpace
  }
}

/// Diagnostics snapshot returned by ``OpenJoystickDriverXPCProtocol/getVirtualDeviceDiagnostics(reply:)``.
public struct XPCVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: String
  /// Output routing mode in the daemon.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  public let outputMode: String
  public let hidGamepads: [XPCHIDGamepadSnapshot]
  /// DriverKit output injection stats (IOHIDDeviceSetReport).
  ///
  /// Present only when the daemon is new enough to report it.
  public let driverKitOutputStats: XPCDriverKitOutputStats?

  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: String,
    outputMode: String,
    hidGamepads: [XPCHIDGamepadSnapshot],
    driverKitOutputStats: XPCDriverKitOutputStats? = nil
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.outputMode = outputMode
    self.hidGamepads = hidGamepads
    self.driverKitOutputStats = driverKitOutputStats
  }
}

/// Stats for DriverKit output injection via IOHIDDeviceSetReport.
public struct XPCDriverKitOutputStats: Codable, Sendable {
  public let attempts: Int
  public let successes: Int
  public let failures: Int
  /// Last IOKit error as hex string (e.g. "0xe00002cd"), or nil if none.
  public let lastErrorHex: String?

  public init(attempts: Int, successes: Int, failures: Int, lastErrorHex: String?) {
    self.attempts = attempts
    self.successes = successes
    self.failures = failures
    self.lastErrorHex = lastErrorHex
  }
}

/// Result of a short "press buttons now" self-test for virtual device input delivery.
public struct XPCVirtualDeviceSelfTestPayload: Codable, Sendable {
  public let seconds: Int
  public let driverKitValueEvents: Int
  public let driverKitReportEvents: Int
  public let userSpaceValueEvents: Int
  public let userSpaceReportEvents: Int
  /// DriverKit-only self-test delta based on the dext IOHID device DebugState InputReportCount.
  public let driverKitInputReportDelta: Int?
  /// DriverKit-only self-test delta based on IOHIDDeviceSetReport successes in the daemon.
  ///
  /// This is reliable even when IOHID input callbacks are flaky during sysext replacement/upgrade.
  public let driverKitSetReportSuccessDelta: Int?

  public init(
    seconds: Int,
    driverKitValueEvents: Int,
    driverKitReportEvents: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    driverKitInputReportDelta: Int? = nil,
    driverKitSetReportSuccessDelta: Int? = nil
  ) {
    self.seconds = seconds
    self.driverKitValueEvents = driverKitValueEvents
    self.driverKitReportEvents = driverKitReportEvents
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.driverKitInputReportDelta = driverKitInputReportDelta
    self.driverKitSetReportSuccessDelta = driverKitSetReportSuccessDelta
  }
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
  /// Whether the user-space virtual gamepad is enabled (IOHIDUserDevice).
  public let userSpaceVirtualDeviceEnabled: Bool?
  /// Short status string for the user-space virtual gamepad (e.g. "on", "off", "error: ...").
  public let userSpaceVirtualDeviceStatus: String?
  /// Virtual device mode (driverKit / compatUserSpace / both).
  public let virtualDeviceMode: String?
  /// Effective output routing mode (primaryOnly / secondaryOnly / both).
  ///
  /// This can differ from `virtualDeviceMode` when the daemon is in `auto` mode.
  public let effectiveOutputMode: String?

  /// Creates a new XPCStatusPayload.
  public init(
    inputMonitoring: String,
    connectedDevices: [XPCDeviceDescription],
    userSpaceVirtualDeviceEnabled: Bool? = nil,
    userSpaceVirtualDeviceStatus: String? = nil,
    virtualDeviceMode: String? = nil,
    effectiveOutputMode: String? = nil
  ) {
    self.inputMonitoring = inputMonitoring
    self.connectedDevices = connectedDevices
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.virtualDeviceMode = virtualDeviceMode
    self.effectiveOutputMode = effectiveOutputMode
  }
}
