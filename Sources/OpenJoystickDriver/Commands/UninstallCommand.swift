import Foundation
import OpenJoystickDriverKit

/// Uninstalls daemon LaunchAgent for current user.
struct UninstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Uninstall")
    do {
      try DaemonManager.uninstall()
      print("Daemon uninstalled.")
    } catch {
      print("Uninstall failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
