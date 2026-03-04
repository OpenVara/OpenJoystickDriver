import Foundation
import OpenJoystickDriverKit

struct StatusCommand {
  func run() {
    debugPrint("OpenJoystickDriver Status")
    let divider = String(repeating: "\u{2500}", count: 25)
    debugPrint(divider)
    debugPrint("")

    let client = XPCClient()
    client.connect()
    let semaphore = DispatchSemaphore(value: 0)
    // nonisolated(unsafe): semaphore ensures sequential access - no data race.
    nonisolated(unsafe) var xpcPayload: XPCStatusPayload?
    Task { @Sendable in
      xpcPayload = try? await client.getStatus()
      semaphore.signal()
    }
    let connected =
      semaphore.wait(timeout: .now() + xpcCallTimeoutSeconds) == .success && xpcPayload != nil

    if connected, let payload = xpcPayload {
      debugPrint("(connected to running daemon via XPC)")
      debugPrint("")
      debugPrint("Permissions:")
      debugPrint("  Input Monitoring : " + payload.inputMonitoring)
      debugPrint("  Accessibility    : " + payload.accessibility)
      debugPrint("")
      if payload.connectedDevices.isEmpty {
        debugPrint("Devices: (none connected)")
      } else {
        debugPrint("Devices" + " (\(payload.connectedDevices.count)):")
        for dev in payload.connectedDevices { debugPrint("  \(dev)") }
      }
    } else {
      client.disconnect()
      runDirectMode()
    }
    debugPrint("")
    debugPrint("Use '--headless list'" + " to enumerate controllers.")
  }

  private func runDirectMode() {
    debugPrint("(direct mode - daemon not running)")
    debugPrint("")
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      let accessState = await permManager.checkAccessibilityState()
      debugPrint("Permissions:")
      debugPrint("  Input Monitoring : " + "\(inputState.label)" + " \(inputState)")
      debugPrint("  Accessibility    : " + "\(accessState.label)" + " \(accessState)")
      if inputState != .granted {
        debugPrint("  -> Grant in: System Settings" + " > Privacy > Input Monitoring")
      }
      if accessState != .granted {
        debugPrint("  -> Grant in: System Settings" + " > Privacy > Accessibility")
      }
    }
  }
}
