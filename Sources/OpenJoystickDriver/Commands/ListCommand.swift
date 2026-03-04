import Foundation
import OpenJoystickDriverKit
import SwiftUSB

struct ListCommand {
  func run() {
    debugPrint("Scanning for game controllers...")
    debugPrint("")

    let client = XPCClient()
    client.connect()
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var xpcDevices: [String]?
    Task { @Sendable in
      xpcDevices = try? await client.listDevices()
      semaphore.signal()
    }
    let daemonRunning =
      semaphore.wait(timeout: .now() + xpcCallTimeoutSeconds) == .success && xpcDevices != nil

    if daemonRunning, let devices = xpcDevices {
      debugPrint("Controllers (from running daemon):")
      if devices.isEmpty {
        debugPrint("  (none connected)")
      } else {
        for dev in devices { debugPrint("  \(dev)") }
      }
      debugPrint("")
      return
    }

    client.disconnect()
    debugPrint("(direct scan - daemon not running)")
    listUSBDevices()
    debugPrint("")
    debugPrint("Note: HID controllers shown" + " when daemon is running.")
  }

  private func listUSBDevices() {
    debugPrint("USB Controllers (class 0xFF / GIP):")
    do {
      let context = try USBContext()
      runSync {
        var found = false
        let stream = context.findDevices(
          deviceClass: USBConstants.DeviceClass.vendorSpecific.rawValue,
          findAll: true
        )
        for await device in stream {
          let id = DeviceIdentifier(vendorID: device.idVendor, productID: device.idProduct)
          let parser = ParserRegistry().parser(for: id)
          let name = String(describing: type(of: parser))
          let vid = String(format: "%04X", device.idVendor)
          let pid = String(format: "%04X", device.idProduct)
          debugPrint(
            "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
              + " parser=\(name)"
          )
          found = true
        }
        if !found { debugPrint("  (none found)") }
      }
    } catch {
      debugPrint("  Error accessing USB: \(error)")
      debugPrint(
        "  Tip: Run with sudo or sign with" + " entitlement" + " (see scripts/sign-dev.sh)"
      )
    }
  }
}
