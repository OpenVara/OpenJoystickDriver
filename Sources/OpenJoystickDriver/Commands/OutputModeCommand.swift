import Foundation
import OpenJoystickDriverKit

struct OutputModeCommand {
  func run(arguments: [String]) {
    guard let arg = arguments.first else {
      print("Usage: OpenJoystickDriver --headless output primary|secondary|both|status")
      return
    }

    func normalize(_ s: String) -> String? {
      switch s {
      case "primary", "primaryOnly", "driverkit", "dext": return "primaryOnly"
      case "secondary", "secondaryOnly", "userspace", "user-space": return "secondaryOnly"
      case "both": return "both"
      default: return nil
      }
    }

    let client = XPCClient()
    client.connect()

    if arg == "status" {
      let mode: String? =
        runSyncResult(timeout: xpcCallTimeoutSeconds) { try? await client.getOutputMode() } ?? nil
      print("output: \(mode ?? "unknown")")
      return
    }

    guard let mode = normalize(arg) else {
      print("Usage: OpenJoystickDriver --headless output primary|secondary|both|status")
      exit(1)
    }

    let ok = runSyncResult {
      do {
        try await client.setOutputMode(mode)
        return true
      } catch {
        return false
      }
    }

    if !ok {
      print("ERROR: failed to set output mode to \(mode) (daemon not running?)")
      exit(1)
    }

    let actual: String? =
      runSyncResult(timeout: xpcCallTimeoutSeconds) { try? await client.getOutputMode() } ?? nil
    print("output: \(actual ?? mode)")
  }
}
