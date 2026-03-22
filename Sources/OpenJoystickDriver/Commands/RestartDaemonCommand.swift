import Foundation
import OpenJoystickDriverKit

struct RestartDaemonCommand {
  func run() {
    guard DaemonManager.isInstalled else {
      print("Daemon is not installed. Run 'install' first.")
      exit(1)
    }
    DaemonManager.restart()
    print("Daemon restarted.")
  }
}
