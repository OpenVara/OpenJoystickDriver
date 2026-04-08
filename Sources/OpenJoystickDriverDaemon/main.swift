import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

let permissionManager = PermissionManager()

// DriverKit virtual HID output is optional and can be enabled/disabled by the GUI via XPC.
// We do not connect eagerly at startup — this avoids "half-active" states where the
// DriverKit virtual device is present but idle while Compatibility is selected.
let dextDispatcher = DextOutputDispatcher()
print("[Daemon] DriverKit output: on-demand (managed by Mode)")

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
