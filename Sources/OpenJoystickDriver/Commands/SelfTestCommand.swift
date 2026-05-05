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
    if let delta = payload.driverKitInputReportDelta {
      print("  DriverKit input report delta: \(delta)")
    }
    if let delta = payload.driverKitSetReportSuccessDelta {
      print("  DriverKit setReport success delta: \(delta)")
    }
    if let delta = payload.driverKitSetReportAttemptDelta {
      print("  DriverKit setReport attempt delta: \(delta)")
    }
    if let delta = payload.driverKitSetReportFailureDelta {
      print("  DriverKit setReport failure delta: \(delta)")
    }
    if let error = payload.driverKitSetReportLastErrorHex {
      print("  DriverKit setReport last error: \(error)")
    }
    if let delta = payload.driverKitConnectionAttemptDelta {
      print("  DriverKit connection attempt delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionSuccessDelta {
      print("  DriverKit connection success delta: \(delta)")
    }
    if let delta = payload.driverKitConnectionFailureDelta {
      print("  DriverKit connection failure delta: \(delta)")
    }
    if let error = payload.driverKitLastConnectionErrorHex {
      print("  DriverKit connection last error: \(error)")
    }
    if let summary = payload.driverKitDiscoverySummary {
      print("  DriverKit discovery: \(summary)")
    }
    print(
      "  User-space: value \(payload.userSpaceValueEvents), report \(payload.userSpaceReportEvents)"
    )
  }
}
