import ApplicationServices
import Foundation
import IOKit
import IOKit.hid

private let permissionPollNanoseconds: UInt64 = 1_000_000_000

/// Manages Input Monitoring and Accessibility permission
/// state for the daemon.
public actor PermissionManager {
  /// The three possible states for a macOS permission.
  public enum AccessState: Sendable, Equatable {
    /// The user has allowed access.
    case granted
    /// The user has denied access, or the system rejected the request.
    case denied
    /// The permission has not been checked yet in this session.
    case unknown

    /// A short status tag suitable for log output or CLI display.
    public var label: String {
      switch self {
      case .granted: return "[OK]"
      case .denied: return "[DENIED]"
      case .unknown: return "[UNKNOWN]"
      }
    }
  }

  /// Current state of the Input Monitoring permission. Updated by ``startPolling()`` and ``requestAccess()``.
  public private(set) var inputMonitoringState: AccessState = .unknown
  /// Current state of the Accessibility permission. Updated by ``startPolling()`` and ``checkAccessibilityState()``.
  public private(set) var accessibilityState: AccessState = .unknown
  private var pollingTask: Task<Void, Never>?

  public init() {}

  /// Check current Input Monitoring permission state
  /// (does not prompt).
  public func checkAccess() -> AccessState {
    let result = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    return mapAccess(result)
  }

  /// Check current Accessibility permission state.
  public func checkAccessibility() -> AccessState { AXIsProcessTrusted() ? .granted : .denied }

  /// Request Input Monitoring permission
  /// (shows system dialog if needed).
  /// Returns updated state.
  @discardableResult public func requestAccess() -> AccessState {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    let state = checkAccess()
    inputMonitoringState = state
    return state
  }

  /// Check and update Accessibility permission state.
  @discardableResult public func checkAccessibilityState() -> AccessState {
    let state = checkAccessibility()
    accessibilityState = state
    return state
  }

  /// Start polling permission state every second
  /// for runtime changes.
  public func startPolling() {
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: permissionPollNanoseconds)
        guard let self else { break }
        let currentInput = await self.checkAccess()
        let prevInput = await self.inputMonitoringState
        if currentInput != prevInput { await self.updateState(currentInput) }
        let currentAccess = await self.checkAccessibility()
        let prevAccess = await self.accessibilityState
        if currentAccess != prevAccess { await self.updateAccessibilityState(currentAccess) }
      }
    }
  }

  /// Stops the background polling task started by ``startPolling()``.
  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func updateState(_ state: AccessState) {
    let previous = inputMonitoringState
    inputMonitoringState = state
    print("[PermissionManager] Input Monitoring " + "state changed: \(previous) -> \(state)")
  }

  private func updateAccessibilityState(_ state: AccessState) {
    let previous = accessibilityState
    accessibilityState = state
    print("[PermissionManager] Accessibility " + "state changed: \(previous) -> \(state)")
  }

  private func mapAccess(_ result: IOHIDAccessType) -> AccessState {
    switch result {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
  }
}
