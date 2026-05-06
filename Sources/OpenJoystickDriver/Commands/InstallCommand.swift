import Foundation
import OpenJoystickDriverKit

/// Installs daemon as LaunchAgent for current user.
struct InstallCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Install")
    // Ensure we are running from inside OpenJoystickDriver.app so daemon registration
    // can find the embedded LaunchAgent plist.
    let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let contentsDir = exeURL.deletingLastPathComponent().deletingLastPathComponent()
    let agentPlist = contentsDir.appendingPathComponent(
      "Library/LaunchAgents/\(DaemonManager.agentPlistName)"
    )
    if !FileManager.default.fileExists(atPath: agentPlist.path) {
      print("ERROR: LaunchAgent plist not found in this app bundle.")
      print("  Expected: \(agentPlist.path)")
      print("")
      print("Fix:")
      print("  Run the /Applications copy: /Applications/OpenJoystickDriver.app")
      exit(1)
    }
    do {
      try DaemonManager.install()
      print("Daemon installed (auto-starts on login).")
    } catch {
      print("Install failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
