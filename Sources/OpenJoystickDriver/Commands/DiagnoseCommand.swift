import Foundation
import OpenJoystickDriverKit
import SwiftUSB

struct DiagnoseCommand {
  func run() {
    print("OpenJoystickDriver Diagnostics")
    let divider = String(repeating: "\u{2550}", count: 30)
    print(divider)
    print("")

    printSystemInfo()
    print("")
    printPermissions()
    print("")
    printUSBDevices()
    print("")
    printTroubleshooting()
  }

  private func printSystemInfo() {
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    print("macOS: \(ver.majorVersion)" + ".\(ver.minorVersion)" + ".\(ver.patchVersion)")
    print("Binary: \(CommandLine.arguments[0])")
  }

  private func printPermissions() {
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      let accessState = await permManager.checkAccessibilityState()
      print("Permissions:")
      print("  Input Monitoring : " + "\(inputState.label) \(inputState)")
      print("  Accessibility    : " + "\(accessState.label) \(accessState)")
    }
  }

  private func printUSBDevices() {
    print("USB Game Controllers (class 0xFF):")
    do {
      let context = try USBContext()
      runSync {
        var found = false
        let stream = context.findDevices(
          deviceClass: USBConstants.DeviceClass.vendorSpecific.rawValue,
          findAll: true
        )
        for await device in stream {
          let vid = String(format: "%04X", device.idVendor)
          let pid = String(format: "%04X", device.idProduct)
          print(
            "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
          )
          found = true
        }
        if !found { print("  (none detected)") }
      }
    } catch { print("  USB access error: \(error)") }
  }

  private func printTroubleshooting() {
    print("Troubleshooting:")
    print("  USB access denied?")
    print(
      "    -> Run: ./scripts/sign-dev.sh" + " && sudo .build/debug/" + "OpenJoystickDriver run"
    )
    print("  No input from controller?")
    print(
      "    -> Grant Input Monitoring:" + " System Settings > Privacy" + " > Input Monitoring"
    )
    print("  Keys not firing?")
    print("    -> Grant Accessibility:" + " System Settings > Privacy" + " > Accessibility")
  }
}
