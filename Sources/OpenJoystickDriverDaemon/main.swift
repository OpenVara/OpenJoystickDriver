import Foundation
import OpenJoystickDriverKit

let permissionManager = PermissionManager()
let profileStore = ProfileStore()
let manager = DeviceManager(dispatcher: CGEventOutputDispatcher(profileStore: profileStore))
let xpcService = XPCService(
  deviceManager: manager,
  permissionManager: permissionManager,
  profileStore: profileStore
)

manager.setupGracefulShutdown(label: "Daemon")

print("[Daemon] OpenJoystickDriverDaemon starting...")

Task { await permissionManager.startPolling() }

Task {
  let accessState = await permissionManager.checkAccessibilityState()
  if accessState != .granted {
    print("[Daemon] Accessibility not granted" + " - CGEvent output disabled")
    print("[Daemon] Grant in System Settings" + " > Privacy > Accessibility," + " then restart")
  }
}

xpcService.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
