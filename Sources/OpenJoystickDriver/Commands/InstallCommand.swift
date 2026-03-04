import Foundation
import OpenJoystickDriverKit

/// Installs daemon as LaunchAgent for current user.
struct InstallCommand {
  func run() {
    let cliURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let daemonURL = cliURL.deletingLastPathComponent().appendingPathComponent(
      "OpenJoystickDriverDaemon"
    )
    guard FileManager.default.fileExists(atPath: daemonURL.path) else {
      print("Error: daemon binary not found at \(daemonURL.path)")
      exit(1)
    }
    do {
      try DaemonManager.install(daemonExecutable: daemonURL)
      print("Daemon installed. Auto-starts on login.")
    } catch {
      print("Install failed: \(error.localizedDescription)")
      exit(1)
    }
  }
}
