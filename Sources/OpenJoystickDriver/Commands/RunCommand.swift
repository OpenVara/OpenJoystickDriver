import Foundation
import OpenJoystickDriverKit

struct RunCommand {
  func run() {
    print("[OpenJoystickDriver] Starting driver...")
    print("[OpenJoystickDriver] Press Ctrl+C to stop.")

    let profileStore = ProfileStore()
    let manager = DeviceManager(dispatcher: CGEventOutputDispatcher(profileStore: profileStore))

    manager.setupGracefulShutdown(label: "OpenJoystickDriver")

    Task { await manager.start() }

    RunLoop.main.run()
  }
}
