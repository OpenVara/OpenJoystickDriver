import Foundation
import OpenJoystickDriverKit

struct RestartDaemonCommand {
  func run() {
    guard DaemonManager.isInstalled else {
      print("Daemon is not installed. Run 'install' first.")
      exit(1)
    }
    do { try DaemonManager.restart() } catch {
      print("Failed to restart daemon: \(error)")
      exit(1)
    }
    print("Daemon restarted.")
  }
}
