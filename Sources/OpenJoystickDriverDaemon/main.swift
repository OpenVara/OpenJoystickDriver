import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

let permissionManager = PermissionManager()

// Always use the DriverKit virtual HID extension. If the dext isn't available yet
// (e.g. pending reboot after first approval), dispatch() will auto-retry on each
// input event until the connection succeeds.
let dextDispatcher = DextOutputDispatcher()
if dextDispatcher.connect() {
  print("[Daemon] Connected to DriverKit virtual HID extension")
} else {
  print("[Daemon] DriverKit extension not yet available — will auto-retry on first device input")
}

// Optional secondary output is controlled by the GUI via XPC (user-space IOHIDUserDevice).
let dispatcher = CompositeOutputDispatcher(primary: dextDispatcher)

let manager = DeviceManager(dispatcher: dispatcher)
let xpcService = XPCService(
  deviceManager: manager,
  permissionManager: permissionManager,
  dispatcher: dispatcher,
  dextDispatcher: dextDispatcher
)

manager.setupGracefulShutdown(label: "Daemon")

print("[Daemon] OpenJoystickDriverDaemon starting...")

Task { await permissionManager.startPolling() }

xpcService.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
