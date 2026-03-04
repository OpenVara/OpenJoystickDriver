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
    case "set": setMapping(store: store, args: Array(args.dropFirst()))
    case "reset": resetProfile(store: store, args: Array(args.dropFirst()))
    default:
      print("Unknown profile subcommand: \(sub)")
      print(
        "Usage: OpenJoystickDriver --headless" + " profile [list|show VID:PID|set VID:PID BUTTON KEYCODE|reset VID:PID]"
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
      for (key, kc) in sorted {
        let buttonLabel = Button(rawValue: key)?.displayName ?? key
        let keyLabel = KeyNames.name(for: kc)
        print("    \(buttonLabel) -> \(keyLabel) (\(kc))")
      }
    }
  }

  private func setMapping(store: ProfileStore, args: [String]) {
    guard args.count == 3,
      let (vid, pid) = parseVidPid(args[0]),
      let button = resolveButton(args[1]),
      let keyCode = resolveKeyCode(args[2])
    else {
      print(
        "Usage: profile set VID:PID BUTTON KEYCODE"
          + "  (e.g. profile set 13623:4112 a 36)"
      )
      print("  BUTTON: a, b, x, y, start, back, guide, lb, rb, dpadup, dpaddown, dpadleft, dpadright")
      print("  KEYCODE: numeric (e.g. 36) or key name (e.g. return, escape, space)")
      return
    }
    let identifier = DeviceIdentifier(vendorID: vid, productID: pid)
    runSync {
      do {
        var profile = await store.profile(for: identifier)
        profile.buttonMappings[button.rawValue] = keyCode
        try await store.save(profile)
        let keyLabel = KeyNames.name(for: keyCode)
        print("Set \(button.displayName) -> \(keyLabel) (\(keyCode)) for \(args[0])")
      } catch { print("Failed to save profile: \(error)") }
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

  private func resolveButton(_ input: String) -> Button? {
    let lower = input.lowercased()
    let aliases: [String: Button] = [
      "lb": .leftBumper, "rb": .rightBumper,
      "lsb": .leftStick, "rsb": .rightStick,
      "dpadup": .dpadUp, "dpaddown": .dpadDown,
      "dpadleft": .dpadLeft, "dpadright": .dpadRight,
    ]
    if let aliased = aliases[lower] { return aliased }
    return Button.allCases.first { $0.rawValue.lowercased() == lower }
  }

  private func resolveKeyCode(_ input: String) -> UInt16? {
    if let numeric = UInt16(input) { return numeric }
    let lower = input.lowercased()
    for (code, name) in KeyNames.lookup {
      if name.lowercased().hasPrefix(lower) { return code }
    }
    return nil
  }
}
