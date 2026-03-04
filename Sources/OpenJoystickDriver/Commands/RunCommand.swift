import Foundation
import OpenJoystickDriverKit

struct RunCommand {
  func run() {
    debugPrint("[OpenJoystickDriver] Starting driver...")
    debugPrint("[OpenJoystickDriver] Press Ctrl+C to stop.")

    let profileStore = ProfileStore()
    let manager = DeviceManager(dispatcher: CGEventOutputDispatcher(profileStore: profileStore))

    manager.setupGracefulShutdown(label: "OpenJoystickDriver")

    Task { await manager.start() }

    RunLoop.main.run()
  }
}
