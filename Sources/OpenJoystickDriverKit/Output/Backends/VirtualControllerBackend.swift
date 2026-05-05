import Foundation

/// Stable identifiers for virtual controller output backends.
public enum VirtualControllerBackendID: String, CaseIterable, Sendable {
  case driverKitHID
  case userSpaceHID
  case gameControllerVirtual
}

/// Static capability description used by diagnostics and backend acceptance loops.
public struct VirtualControllerBackendCapabilities: Equatable, Sendable {
  public let isSystemWide: Bool
  public let supportsMultiplePhysicalControllers: Bool
  public let requiresEntitlement: Bool
  public let isImplemented: Bool
  public let notes: String

  public init(
    isSystemWide: Bool,
    supportsMultiplePhysicalControllers: Bool,
    requiresEntitlement: Bool,
    isImplemented: Bool,
    notes: String
  ) {
    self.isSystemWide = isSystemWide
    self.supportsMultiplePhysicalControllers = supportsMultiplePhysicalControllers
    self.requiresEntitlement = requiresEntitlement
    self.isImplemented = isImplemented
    self.notes = notes
  }
}

/// Runtime status for one virtual controller backend.
public struct VirtualControllerBackendStatus: Equatable, Sendable {
  public let id: VirtualControllerBackendID
  public let isRunning: Bool
  public let detail: String

  public init(id: VirtualControllerBackendID, isRunning: Bool, detail: String) {
    self.id = id
    self.isRunning = isRunning
    self.detail = detail
  }
}

/// Output backend contract for publishing normalized controller state to macOS consumers.
public protocol VirtualControllerBackend: OutputDispatcher {
  var backendID: VirtualControllerBackendID { get }
  var capabilities: VirtualControllerBackendCapabilities { get }

  @discardableResult func startBackend() async -> VirtualControllerBackendStatus
  func stopBackend() async
  func backendStatus() -> VirtualControllerBackendStatus
}

public enum VirtualControllerBackendCatalog {
  public static let gameControllerVirtualCapabilities = VirtualControllerBackendCapabilities(
    isSystemWide: false,
    supportsMultiplePhysicalControllers: false,
    requiresEntitlement: false,
    isImplemented: false,
    notes: "Apple GCVirtualController is documented as a game-local software controller, not a system-wide virtual device."
  )
}

extension DextOutputDispatcher: VirtualControllerBackend {
  public var backendID: VirtualControllerBackendID { .driverKitHID }

  public var capabilities: VirtualControllerBackendCapabilities {
    VirtualControllerBackendCapabilities(
      isSystemWide: true,
      supportsMultiplePhysicalControllers: false,
      requiresEntitlement: true,
      isImplemented: true,
      notes: "DriverKit IOUserHIDDevice output path."
    )
  }

  public func startBackend() async -> VirtualControllerBackendStatus {
    setEnabled(true)
    let connected = connect()
    return VirtualControllerBackendStatus(
      id: backendID,
      isRunning: connected,
      detail: connected ? "connected" : "virtual HID device not found"
    )
  }

  public func stopBackend() async {
    setEnabled(false)
  }

  public func backendStatus() -> VirtualControllerBackendStatus {
    let connected = isConnected()
    return VirtualControllerBackendStatus(
      id: backendID,
      isRunning: connected,
      detail: connected ? "connected" : "not connected"
    )
  }
}

extension UserSpaceOutputDispatcher: VirtualControllerBackend {
  public var backendID: VirtualControllerBackendID { .userSpaceHID }

  public var capabilities: VirtualControllerBackendCapabilities {
    VirtualControllerBackendCapabilities(
      isSystemWide: true,
      supportsMultiplePhysicalControllers: true,
      requiresEntitlement: true,
      isImplemented: true,
      notes: "IOHIDUserDevice compatibility output path."
    )
  }

  public func startBackend() async -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(id: backendID, isRunning: true, detail: status)
  }

  public func stopBackend() async {
    close()
  }

  public func backendStatus() -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(id: backendID, isRunning: status != "off", detail: status)
  }
}
