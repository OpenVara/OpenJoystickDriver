import Foundation
import OpenJoystickDriverKit

struct StartDaemonCommand {
  func run() {
    guard DaemonManager.isInstalled else {
      print("Daemon is not installed. Run 'install' first.")
      exit(1)
    }
    DaemonManager.start()
    print("Daemon started.")
  }
}
