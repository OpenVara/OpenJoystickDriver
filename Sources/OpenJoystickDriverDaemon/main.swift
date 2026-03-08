import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

let permissionManager = PermissionManager()
let profileStore = ProfileStore()

// Prefer the DriverKit virtual HID extension (no hid.virtual.device entitlement
// required). Fall back to IOHIDUserDevice if the extension is not installed yet.
let dextDispatcher = DextOutputDispatcher(profileStore: profileStore)
let dispatcher: any OutputDispatcher
if dextDispatcher.connect() {
  dispatcher = dextDispatcher
  print("[Daemon] Using DextOutputDispatcher (DriverKit virtual HID)")
} else {
  dispatcher = IOHIDVirtualOutputDispatcher(profileStore: profileStore)
  print("[Daemon] Using IOHIDVirtualOutputDispatcher (fallback — install dext for production)")
}

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

xpcService.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
