import Foundation
import OpenJoystickDriverKit

struct StartDaemonCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Start")
    guard DaemonManager.isInstalled else {
      print("Daemon is not installed. Run 'install' first.")
      exit(1)
    }
    do { try DaemonManager.start() } catch {
      print("Failed to start daemon: \(error)")
      exit(1)
    }
    print("Daemon started.")
  }
}
