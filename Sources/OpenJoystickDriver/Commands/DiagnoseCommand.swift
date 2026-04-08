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
    printSystemExtensionBundle()
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

  private func printSystemExtensionBundle() {
    let appPath = "/Applications/OpenJoystickDriver.app"
    let sysextDir = appPath + "/Contents/Library/SystemExtensions"
    let expectedID = "com.openjoystickdriver.VirtualHIDDevice"
    let expectedDextPath = sysextDir + "/com.openjoystickdriver.VirtualHIDDevice.dext"

    print("DriverKit System Extension (in /Applications):")

    let fm = FileManager.default
    guard fm.fileExists(atPath: appPath) else {
      print("  App: missing at \(appPath)")
      print("  Fix: build + install the app to /Applications")
      return
    }

    print("  App: present")
    print("  Expected .dext: \(expectedDextPath)")

    guard fm.fileExists(atPath: sysextDir) else {
      print("  Result: FAIL (missing SystemExtensions folder)")
      print("  Fix: rebuild with ./scripts/build-dext.sh and reopen the /Applications copy")
      return
    }

    let items = (try? fm.contentsOfDirectory(atPath: sysextDir)) ?? []
    let dexts = items.filter { $0.hasSuffix(".dext") }.sorted()
    if dexts.isEmpty {
      print("  Result: FAIL (no .dext bundles found)")
      print("  Fix: rebuild with ./scripts/build-dext.sh and reopen the /Applications copy")
      return
    }

    print("  Found .dext bundles:")
    var foundExpected = false
    for d in dexts {
      let path = sysextDir + "/" + d
      let bid = Bundle(path: path)?.bundleIdentifier ?? "UNKNOWN"
      print("    - \(d) (id: \(bid))")
      if bid == expectedID { foundExpected = true }
    }

    if foundExpected {
      print("  Result: PASS (expected id present: \(expectedID))")
    } else {
      print("  Result: FAIL (expected id missing: \(expectedID))")
      print("  Fix: rebuild with ./scripts/build-dext.sh and reopen the /Applications copy")
    }
  }

  private func printPermissions() {
    let permManager = PermissionManager()
    runSync {
      let inputState = await permManager.checkAccess()
      print("Permissions:")
      print("  Input Monitoring : " + "\(inputState.label) \(inputState)")
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
    print("    -> Run: ./scripts/sign-dev.sh" + " && sudo .build/debug/" + "OpenJoystickDriver run")
    print("  No input from controller?")
    print("    -> Grant Input Monitoring:" + " System Settings > Privacy" + " > Input Monitoring")
  }
}
