import Foundation
import OpenJoystickDriverKit

struct SelfTestCommand {
  func run(arguments: [String]) {
    let seconds: Int
    if let first = arguments.first, let parsed = Int(first), parsed > 0 {
      seconds = parsed
    } else {
      seconds = 5
    }

    let client = XPCClient()
    client.connect()

    let payload = runSyncResult { try? await client.runVirtualDeviceSelfTest(seconds: seconds) }
    guard let payload else {
      print("ERROR: self-test failed (daemon not running?)")
      exit(1)
    }

    print("Virtual device self-test (\(payload.seconds)s)")
    print("  DriverKit: value \(payload.driverKitValueEvents), report \(payload.driverKitReportEvents)")
    print(
      "  User-space: value \(payload.userSpaceValueEvents), report \(payload.userSpaceReportEvents)"
    )
  }
}

