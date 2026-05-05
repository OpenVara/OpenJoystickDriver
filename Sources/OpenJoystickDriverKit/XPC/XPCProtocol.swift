import Foundation

/// Mach service name shared by the daemon and any client (GUI or CLI).
///
/// Both sides must use the same name to establish a connection.
public let xpcServiceName = "com.openjoystickdriver.xpc"

/// Which identity/protocol the user-space Compatibility virtual device should publish.
///
/// IMPORTANT:
/// - `sdl-macos` is the mature macOS SDL/Steam/PCSX2 path: OJD-owned identity plus
///   an explicit SDL mapping.
/// - `generic-hid` is a plain OJD HID GamePad for consumers that inspect descriptors directly.
/// - `xone-hid` and `x360-hid` are hardware-spoof profiles. They are only correct for
///   consumers whose expected descriptor/report layout exactly matches the selected profile.
public enum CompatibilityIdentity: Codable, CaseIterable, Sendable, Equatable {
  case genericHID
  case sdlMacOS
  case x360HID
  case xoneHID

  public static let allCases: [CompatibilityIdentity] = [
    .genericHID,
    .sdlMacOS,
    .x360HID,
    .xoneHID,
  ]

  public init?(rawValue: String) {
    switch rawValue {
    case "generic-hid":
      self = .genericHID
    case "sdl-macos":
      self = .sdlMacOS
    case "x360-hid":
      self = .x360HID
    case "xone-hid":
      self = .xoneHID
    default:
      return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .genericHID: "generic-hid"
    case .sdlMacOS: "sdl-macos"
    case .x360HID: "x360-hid"
    case .xoneHID: "xone-hid"
    }
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown compatibility identity: \(raw)")
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var disablesDriverKitMirror: Bool {
    switch self {
    case .genericHID, .sdlMacOS:
      true
    case .xoneHID, .x360HID:
      false
    }
  }
}

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

  /// Sends a short physical rumble command to a connected USB controller.
  @objc func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    left: Int,
    right: Int,
    lt: Int,
    rt: Int,
    durationMs: Int,
    reply: @escaping (Bool) -> Void
  )

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

  /// Sets which identity/protocol to emulate in Compatibility mode (user-space IOHIDUserDevice).
  ///
  /// Values: "generic-hid", "sdl-macos", "x360-hid", "xone-hid".
  @objc func setCompatibilityIdentity(_ raw: String, reply: @escaping (Bool) -> Void)

  /// Gets which identity/protocol is configured for Compatibility mode.
  @objc func getCompatibilityIdentity(reply: @escaping (String) -> Void)

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

  /// Resets daemon persisted settings (mode/output/compat identity) to defaults.
  @objc func resetSettings(reply: @escaping (Bool) -> Void)
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
  public let connectionAttempts: Int
  public let connectionSuccesses: Int
  public let connectionFailures: Int
  public let lastConnectionErrorHex: String?
  public let lastDiscoverySummary: String?

  public init(
    attempts: Int,
    successes: Int,
    failures: Int,
    lastErrorHex: String?,
    connectionAttempts: Int = 0,
    connectionSuccesses: Int = 0,
    connectionFailures: Int = 0,
    lastConnectionErrorHex: String? = nil,
    lastDiscoverySummary: String? = nil
  ) {
    self.attempts = attempts
    self.successes = successes
    self.failures = failures
    self.lastErrorHex = lastErrorHex
    self.connectionAttempts = connectionAttempts
    self.connectionSuccesses = connectionSuccesses
    self.connectionFailures = connectionFailures
    self.lastConnectionErrorHex = lastConnectionErrorHex
    self.lastDiscoverySummary = lastDiscoverySummary
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
  /// Number of IOHIDDeviceSetReport attempts made by the daemon during the self-test.
  public let driverKitSetReportAttemptDelta: Int?
  /// Number of IOHIDDeviceSetReport failures made by the daemon during the self-test.
  public let driverKitSetReportFailureDelta: Int?
  /// Last IOHIDDeviceSetReport error observed by the daemon, if any.
  public let driverKitSetReportLastErrorHex: String?
  public let driverKitConnectionAttemptDelta: Int?
  public let driverKitConnectionSuccessDelta: Int?
  public let driverKitConnectionFailureDelta: Int?
  public let driverKitLastConnectionErrorHex: String?
  public let driverKitDiscoverySummary: String?

  public init(
    seconds: Int,
    driverKitValueEvents: Int,
    driverKitReportEvents: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    driverKitInputReportDelta: Int? = nil,
    driverKitSetReportSuccessDelta: Int? = nil,
    driverKitSetReportAttemptDelta: Int? = nil,
    driverKitSetReportFailureDelta: Int? = nil,
    driverKitSetReportLastErrorHex: String? = nil,
    driverKitConnectionAttemptDelta: Int? = nil,
    driverKitConnectionSuccessDelta: Int? = nil,
    driverKitConnectionFailureDelta: Int? = nil,
    driverKitLastConnectionErrorHex: String? = nil,
    driverKitDiscoverySummary: String? = nil
  ) {
    self.seconds = seconds
    self.driverKitValueEvents = driverKitValueEvents
    self.driverKitReportEvents = driverKitReportEvents
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.driverKitInputReportDelta = driverKitInputReportDelta
    self.driverKitSetReportSuccessDelta = driverKitSetReportSuccessDelta
    self.driverKitSetReportAttemptDelta = driverKitSetReportAttemptDelta
    self.driverKitSetReportFailureDelta = driverKitSetReportFailureDelta
    self.driverKitSetReportLastErrorHex = driverKitSetReportLastErrorHex
    self.driverKitConnectionAttemptDelta = driverKitConnectionAttemptDelta
    self.driverKitConnectionSuccessDelta = driverKitConnectionSuccessDelta
    self.driverKitConnectionFailureDelta = driverKitConnectionFailureDelta
    self.driverKitLastConnectionErrorHex = driverKitLastConnectionErrorHex
    self.driverKitDiscoverySummary = driverKitDiscoverySummary
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
  /// Source-backed protocol variant (for example, "xboxOne" or "dualShock4").
  public let protocolVariant: String
  /// Source-backed mapping quirks from the controller profile.
  public let mappingFlags: [String]
  /// Interrupt IN endpoint address used by USB transports.
  public let inputEndpoint: UInt8
  /// Interrupt OUT endpoint address used by USB transports.
  public let outputEndpoint: UInt8
  /// Whether the USB pipeline calls setConfiguration(1) before claiming.
  public let needsSetConfiguration: Bool
  /// Post-handshake settle delay in milliseconds.
  public let postHandshakeSettleMs: Int
  /// Preferred virtual output backends from the controller profile.
  public let preferredBackends: [String]
  /// Whether the active physical parser can send source-controller rumble.
  public let supportsPhysicalRumble: Bool

  private enum CodingKeys: String, CodingKey {
    case name
    case vendorID
    case productID
    case parser
    case connection
    case serialNumber
    case protocolVariant
    case mappingFlags
    case inputEndpoint
    case outputEndpoint
    case needsSetConfiguration
    case postHandshakeSettleMs
    case preferredBackends
    case supportsPhysicalRumble
  }

  /// Creates a new XPCDeviceDescription.
  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    parser: String,
    connection: String,
    serialNumber: String?,
    protocolVariant: String = "unknown",
    mappingFlags: [String] = [],
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    supportsPhysicalRumble: Bool = false
  ) {
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.parser = parser
    self.connection = connection
    self.serialNumber = serialNumber
    self.protocolVariant = protocolVariant
    self.mappingFlags = mappingFlags
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleMs = postHandshakeSettleMs
    self.preferredBackends = preferredBackends
    self.supportsPhysicalRumble = supportsPhysicalRumble
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(String.self, forKey: .name)
    self.vendorID = try container.decode(UInt16.self, forKey: .vendorID)
    self.productID = try container.decode(UInt16.self, forKey: .productID)
    self.parser = try container.decode(String.self, forKey: .parser)
    self.connection = try container.decode(String.self, forKey: .connection)
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.protocolVariant =
      try container.decodeIfPresent(String.self, forKey: .protocolVariant) ?? "unknown"
    self.mappingFlags = try container.decodeIfPresent([String].self, forKey: .mappingFlags) ?? []
    self.inputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .inputEndpoint) ?? 0
    self.outputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .outputEndpoint) ?? 0
    self.needsSetConfiguration =
      try container.decodeIfPresent(Bool.self, forKey: .needsSetConfiguration) ?? false
    self.postHandshakeSettleMs =
      try container.decodeIfPresent(Int.self, forKey: .postHandshakeSettleMs) ?? 0
    self.preferredBackends =
      try container.decodeIfPresent([String].self, forKey: .preferredBackends) ?? []
    self.supportsPhysicalRumble =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPhysicalRumble) ?? false
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
  /// Compatibility mode identity/protocol selection.
  public let compatibilityIdentity: String?

  /// Creates a new XPCStatusPayload.
  public init(
    inputMonitoring: String,
    connectedDevices: [XPCDeviceDescription],
    userSpaceVirtualDeviceEnabled: Bool? = nil,
    userSpaceVirtualDeviceStatus: String? = nil,
    virtualDeviceMode: String? = nil,
    effectiveOutputMode: String? = nil,
    compatibilityIdentity: String? = nil
  ) {
    self.inputMonitoring = inputMonitoring
    self.connectedDevices = connectedDevices
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.virtualDeviceMode = virtualDeviceMode
    self.effectiveOutputMode = effectiveOutputMode
    self.compatibilityIdentity = compatibilityIdentity
  }
}
