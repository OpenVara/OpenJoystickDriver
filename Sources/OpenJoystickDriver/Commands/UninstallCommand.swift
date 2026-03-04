import Foundation
import OpenJoystickDriverKit

/// Uninstalls daemon LaunchAgent for current user.
struct UninstallCommand {
  func run() {
    do {
      try DaemonManager.uninstall()
      debugPrint("Daemon uninstalled.")
    } catch {
      debugPrint("Uninstall failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
