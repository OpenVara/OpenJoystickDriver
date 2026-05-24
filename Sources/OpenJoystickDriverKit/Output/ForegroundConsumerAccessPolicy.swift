import Foundation

/// Evaluates whether controller output should remain active based on which app
/// is frontmost and which app bundles currently hold an OpenJoystickDriver
/// virtual HID client open.
public enum ForegroundConsumerAccessPolicy {
  /// Returns true when output should remain active.
  ///
  /// Rules:
  /// - If no consumer app bundle currently has the virtual device open, keep output active.
  /// - Otherwise, keep output active only when the frontmost app bundle matches one of the
  ///   current consumer app bundles.
  public static func allowsOutput(
    frontmostBundleRootPath: String?,
    consumerBundleRootPaths: Set<String>
  ) -> Bool {
    guard !consumerBundleRootPaths.isEmpty else { return true }
    guard let frontmostBundleRootPath else { return false }
    return consumerBundleRootPaths.contains(frontmostBundleRootPath)
  }
}
