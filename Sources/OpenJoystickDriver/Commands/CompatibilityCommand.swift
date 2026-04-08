import Foundation
import OpenJoystickDriverKit

struct CompatibilityCommand {
  func run(arguments: [String]) {
    guard let sub = arguments.first else {
      print("Usage: OpenJoystickDriver --headless compat generic|xboxOne|xbox360|status")
      return
    }

    let client = XPCClient()
    client.connect()

    if sub == "status" {
      let status = runSyncResult { try? await client.getStatus() }
      if let id = status?.compatibilityIdentity {
        print("compatibility identity: \(id)")
      } else {
        print("compatibility identity: unknown")
      }
      return
    }

    guard CompatibilityIdentity(rawValue: sub) != nil else {
      print("Usage: OpenJoystickDriver --headless compat generic|xboxOne|xbox360|status")
      exit(1)
    }

    let ok = runSyncResult {
      do {
        try await client.setCompatibilityIdentity(sub)
        return true
      } catch {
        return false
      }
    }

    if !ok {
      print("ERROR: failed to set compatibility identity to \(sub) (daemon not running?)")
      exit(1)
    }

    let status = runSyncResult { try? await client.getStatus() }
    print("compatibility identity: \(status?.compatibilityIdentity ?? sub)")
    if let s = status?.userSpaceVirtualDeviceStatus {
      print("user-space status: \(s)")
    }
  }
}

