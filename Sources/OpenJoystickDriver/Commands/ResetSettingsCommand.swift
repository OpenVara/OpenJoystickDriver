import Foundation
import OpenJoystickDriverKit

struct ResetSettingsCommand {
  func run() {
    let client = XPCClient()
    client.connect()

    let ok = runSyncResult {
      do {
        return try await client.resetSettings()
      } catch {
        return false
      }
    } ?? false

    if !ok {
      print("ERROR: failed to reset settings (daemon not running?)")
      exit(1)
    }

    print("OK: reset daemon settings.")
    print("Next: open the menubar app, set Mode → Compatibility, then pick Compatibility identity.")
  }
}

