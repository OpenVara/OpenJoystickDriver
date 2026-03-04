import Foundation
import OpenJoystickDriverKit
import SwiftUSB

struct DiagnoseCommand {
  func run() {
    debugPrint("OpenJoystickDriver Diagnostics")
    let divider = String(repeating: "\u{2550}", count: 30)
    debugPrint(divider)
    debugPrint("")

    printSystemInfo()
    debugPrint("")
    printPermissions()
    debugPrint("")
    printUSBDevices()
    debugPrint("")
    printTroubleshooting()
  }

  private func printSystemInfo() {
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    debugPrint("macOS: \(ver.majorVersion)" + ".\(ver.minorVersion)" + ".\(ver.patchVersion)")
    debugPrint("Binary: \(CommandLine.arguments[0])")
  }

  private func printPermissions() {
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      let accessState = await permManager.checkAccessibilityState()
      debugPrint("Permissions:")
      debugPrint("  Input Monitoring : " + "\(inputState.label) \(inputState)")
      debugPrint("  Accessibility    : " + "\(accessState.label) \(accessState)")
    }
  }

  private func printUSBDevices() {
    debugPrint("USB Game Controllers (class 0xFF):")
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
          debugPrint(
            "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
          )
          found = true
        }
        if !found { debugPrint("  (none detected)") }
      }
    } catch { debugPrint("  USB access error: \(error)") }
  }

  private func printTroubleshooting() {
    debugPrint("Troubleshooting:")
    debugPrint("  USB access denied?")
    debugPrint(
      "    -> Run: ./scripts/sign-dev.sh" + " && sudo .build/debug/" + "OpenJoystickDriver run"
    )
    debugPrint("  No input from controller?")
    debugPrint(
      "    -> Grant Input Monitoring:" + " System Settings > Privacy" + " > Input Monitoring"
    )
    debugPrint("  Keys not firing?")
    debugPrint("    -> Grant Accessibility:" + " System Settings > Privacy" + " > Accessibility")
  }
}
