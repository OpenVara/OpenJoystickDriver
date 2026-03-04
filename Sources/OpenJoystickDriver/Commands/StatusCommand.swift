import Foundation
import OpenJoystickDriverKit

struct StatusCommand {
  func run() {
    print("OpenJoystickDriver Status")
    let divider = String(repeating: "\u{2500}", count: 25)
    print(divider)
    print("")

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
      print("(connected to running daemon via XPC)")
      print("")
      print("Permissions:")
      print("  Input Monitoring : " + payload.inputMonitoring)
      print("  Accessibility    : " + payload.accessibility)
      print("")
      if payload.connectedDevices.isEmpty {
        print("Devices: (none connected)")
      } else {
        print("Devices" + " (\(payload.connectedDevices.count)):")
        for dev in payload.connectedDevices { print("  \(dev)") }
      }
    } else {
      client.disconnect()
      runDirectMode()
    }
    print("")
    print("Use '--headless list'" + " to enumerate controllers.")
  }

  private func runDirectMode() {
    print("(direct mode - daemon not running)")
    print("")
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      let accessState = await permManager.checkAccessibilityState()
      print("Permissions:")
      print("  Input Monitoring : " + "\(inputState.label)" + " \(inputState)")
      print("  Accessibility    : " + "\(accessState.label)" + " \(accessState)")
      if inputState != .granted {
        print("  -> Grant in: System Settings" + " > Privacy > Input Monitoring")
      }
      if accessState != .granted {
        print("  -> Grant in: System Settings" + " > Privacy > Accessibility")
      }
    }
  }
}
