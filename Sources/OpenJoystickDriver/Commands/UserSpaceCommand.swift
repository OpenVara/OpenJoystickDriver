import Foundation
import OpenJoystickDriverKit

struct UserSpaceCommand {
  func run(arguments: [String]) {
    guard let sub = arguments.first else {
      print("Usage: OpenJoystickDriver --headless userspace on|off|status")
      return
    }

    let client = XPCClient()
    client.connect()

    switch sub {
    case "on":
      let ok = runSyncResult {
        do {
          try await client.setUserSpaceVirtualDeviceEnabled(true)
          return true
        } catch {
          return false
        }
      }
      if !ok {
        print("ERROR: failed to enable user-space virtual gamepad (daemon not running?)")
        exit(1)
      }
      let status = runSyncResult { try? await client.getStatus() }
      print("user-space: enabled")
      if let s = status?.userSpaceVirtualDeviceStatus { print("status: \(s)") }
    case "off":
      let ok = runSyncResult {
        do {
          try await client.setUserSpaceVirtualDeviceEnabled(false)
          return true
        } catch {
          return false
        }
      }
      if !ok {
        print("ERROR: failed to disable user-space virtual gamepad (daemon not running?)")
        exit(1)
      }
      print("user-space: disabled")
    case "status":
      let enabled = runSyncResult { try? await client.getUserSpaceVirtualDeviceEnabled() }
      let status = runSyncResult { try? await client.getUserSpaceVirtualDeviceStatus() }
      print("user-space: " + ((enabled ?? false) ? "enabled" : "disabled"))
      if let status { print("status: \(status)") }
    default:
      print("Usage: OpenJoystickDriver --headless userspace on|off|status")
      exit(1)
    }
  }
}

