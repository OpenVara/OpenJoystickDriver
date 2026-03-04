import ApplicationServices
import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

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
    print("[Daemon] Grant in System Settings" + " > Privacy > Accessibility")
    // Trigger accessibility TCC prompt for this daemon binary.
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }
}

xpcService.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
