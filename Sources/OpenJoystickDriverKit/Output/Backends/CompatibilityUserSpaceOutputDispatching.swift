import Foundation

/// Common interface for Compatibility user-space HID outputs.
public protocol CompatibilityUserSpaceOutputDispatching: OutputDispatcher {
  /// Human-readable backend status for UI/CLI reporting.
  var status: String { get }
  /// Most recent app-originated rumble report summary, or `"none"`.
  var lastRumbleStatus: String { get }
  /// Tears down any user-space virtual HID devices owned by this output.
  func close()
}
