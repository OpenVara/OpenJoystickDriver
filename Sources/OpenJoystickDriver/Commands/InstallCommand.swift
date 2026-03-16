import Foundation
import OpenJoystickDriverKit

/// Installs daemon as LaunchAgent for current user.
struct InstallCommand {
  func run() {
    let cliURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let macosDir = cliURL.deletingLastPathComponent()
    // Prefer daemon inside its own bundle (required for provisioning profile on macOS 26+)
    let daemonSubpath = "OpenJoystickDriverDaemon.app/Contents/MacOS" + "/OpenJoystickDriverDaemon"
    let bundledDaemon = macosDir.appendingPathComponent(daemonSubpath)
    let legacyDaemon = macosDir.appendingPathComponent("OpenJoystickDriverDaemon")
    let daemonURL =
      FileManager.default.fileExists(atPath: bundledDaemon.path) ? bundledDaemon : legacyDaemon
    guard FileManager.default.fileExists(atPath: daemonURL.path) else {
      print("Error: daemon binary not found at \(bundledDaemon.path) or \(legacyDaemon.path)")
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
