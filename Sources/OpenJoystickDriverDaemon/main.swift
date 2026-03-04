import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

let permissionManager = PermissionManager()
let profileStore = ProfileStore()
let dispatcher = CGEventOutputDispatcher(profileStore: profileStore)
let manager = DeviceManager(dispatcher: dispatcher)
let xpcService = XPCService(
  deviceManager: manager,
  permissionManager: permissionManager,
  profileStore: profileStore,
  dispatcher: dispatcher
)

manager.setupGracefulShutdown(label: "Daemon")

print("[Daemon] OpenJoystickDriverDaemon starting...")

Task { await permissionManager.startPolling() }

Task {
  let accessState = await permissionManager.checkAccessibilityState()
  if accessState != .granted {
    print("[Daemon] Accessibility not granted - CGEvent output disabled")
    print("[Daemon] Grant in System Settings > Privacy > Accessibility")
  }
}

xpcService.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
