import Foundation
import OpenJoystickDriverKit

struct RunCommand {
  func run() {
    print("[OpenJoystickDriver] Starting driver...")
    print("[OpenJoystickDriver] Press Ctrl+C to stop.")

    let profileStore = ProfileStore()
    let dispatcher = DextOutputDispatcher(profileStore: profileStore)
    let manager = DeviceManager(dispatcher: dispatcher)

    manager.setupGracefulShutdown(label: "OpenJoystickDriver")

    Task { await manager.start() }

    RunLoop.main.run()
  }
}
