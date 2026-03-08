import Foundation
import OpenJoystickDriverKit

struct StatusCommand {
  func run() {
    printHeader()
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
      printPayloadStatus(payload)
    } else {
      client.disconnect()
      runDirectMode()
    }
    print("")
    printUsageHint()
  }

  private func printHeader() {
    print("OpenJoystickDriver Status")
    let divider = String(repeating: "\u{2500}", count: 25)
    print(divider)
    print("")
  }

  private func printPayloadStatus(_ payload: XPCStatusPayload) {
    print("(connected to running daemon via XPC)")
    print("")
    print("Permissions:")
    print("  Input Monitoring : " + payload.inputMonitoring)
    print("")
    if payload.connectedDevices.isEmpty {
      print("Devices: (none connected)")
    } else {
      print("Devices" + " (\(payload.connectedDevices.count)):")
      for dev in payload.connectedDevices { print("  \(dev)") }
    }
  }

  private func printUsageHint() { print("Use '--headless list'" + " to enumerate controllers.") }

  private func runDirectMode() {
    print("(direct mode - daemon not running)")
    print("")
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      print("Permissions:")
      print("  Input Monitoring : " + "\(inputState.label)" + " \(inputState)")
      if inputState != .granted {
        print("  -> Grant in: System Settings" + " > Privacy > Input Monitoring")
      }
    }
  }
}
