import Foundation
import OpenJoystickDriverKit

struct ProfileCommand {
  let args: [String]

  init(args: [String] = []) { self.args = args }

  func run() {
    let store = ProfileStore()
    let sub = args.first ?? "list"
    switch sub {
    case "list": listProfiles(store: store)
    case "show": showProfile(store: store, args: Array(args.dropFirst()))
    case "reset": resetProfile(store: store, args: Array(args.dropFirst()))
    default:
      print("Unknown profile subcommand: \(sub)")
      print(
        "Usage: OpenJoystickDriver --headless" + " profile [list|show VID:PID|reset VID:PID]"
      )
    }
  }

  private func listProfiles(store: ProfileStore) {
    runSync {
      let profiles = await store.listProfiles()
      if profiles.isEmpty {
        print("No saved profiles.")
        print("Profiles are created automatically" + " when controller is used.")
      } else {
        print("Saved profiles:")
        for profile in profiles {
          let vid = String(format: "0x%04X", profile.vendorID)
          let pid = String(format: "0x%04X", profile.productID)
          print("  \(vid):\(pid)  '\(profile.name)'" + "  deadzone=\(profile.stickDeadzone)")
        }
      }
    }
  }

  private func showProfile(store: ProfileStore, args: [String]) {
    guard let vidPid = args.first, let (vid, pid) = parseVidPid(vidPid) else {
      print("Usage: profile show VID:PID" + "  (e.g. profile show 13623:4112)")
      return
    }
    let identifier = DeviceIdentifier(vendorID: vid, productID: pid)
    runSync {
      let profile = await store.profile(for: identifier)
      print("Profile for \(vidPid):")
      print("  Name       : \(profile.name)")
      print("  Deadzone   : \(profile.stickDeadzone)")
      print("  Mouse sens : " + "\(profile.stickMouseSensitivity)")
      print("  Scroll sens: " + "\(profile.stickScrollSensitivity)")
      print("  Button mappings:")
      let sorted = profile.buttonMappings.sorted { $0.key < $1.key }
      for (btn, kc) in sorted { print("    \(btn) -> keyCode \(kc)") }
    }
  }

  private func resetProfile(store: ProfileStore, args: [String]) {
    guard let vidPid = args.first, let (vid, pid) = parseVidPid(vidPid) else {
      print("Usage: profile reset VID:PID" + "  (e.g. profile reset 13623:4112)")
      return
    }
    let identifier = DeviceIdentifier(vendorID: vid, productID: pid)
    runSync {
      do {
        try await store.reset(for: identifier)
        print("Profile reset to defaults for \(vidPid)")
      } catch { print("Failed to reset profile: \(error)") }
    }
  }

  private func parseVidPid(_ input: String) -> (UInt16, UInt16)? {
    let parts = input.split(separator: ":")
    guard parts.count == 2, let vid = UInt16(parts[0]), let pid = UInt16(parts[1]) else {
      return nil
    }
    return (vid, pid)
  }
}
