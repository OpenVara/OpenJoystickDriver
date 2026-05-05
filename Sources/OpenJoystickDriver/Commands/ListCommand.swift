import Foundation
import OpenJoystickDriverKit
import SwiftUSB

struct ListCommand {
  func run() {
    print("Scanning for game controllers...")
    print("")
    if checkDaemonAndListDevices() { return }
    handleDirectScan()
  }

  private func checkDaemonAndListDevices() -> Bool {
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

    defer { client.disconnect() }

    guard daemonRunning, let devices = xpcDevices else { return false }
    print("Controllers (from running daemon):")
    if devices.isEmpty {
      print("  (none connected)")
    } else {
      for dev in devices { print("  \(dev)") }
    }
    print("")
    return true
  }

  private func handleDirectScan() {
    print("(direct scan - daemon not running)")
    listUSBDevices()
    print("")
    print("Note: HID controllers shown" + " when daemon is running.")
  }

  private func listUSBDevices() {
    print("USB Controllers (class 0xFF / GIP):")
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
          let profile = ParserRegistry().runtimeProfile(for: id)
          let vid = String(format: "%04X", device.idVendor)
          let pid = String(format: "%04X", device.idProduct)
          let mappings =
            profile.mappingFlags.isEmpty ? "none" : profile.mappingFlags.joined(separator: ",")
          print(
            "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
              + " parser=\(profile.parserName)"
              + " protocol=\(profile.protocolVariant.rawValue)"
              + " endpoints=in:0x\(String(profile.transportProfile.inputEndpoint, radix: 16))"
              + " out:0x\(String(profile.transportProfile.outputEndpoint, radix: 16))"
              + " mappings=\(mappings)"
          )
          found = true
        }
        if !found { print("  (none found)") }
      }
    } catch {
      print("  Error accessing USB: \(error)")
      print("  Tip: Run with sudo or sign with" + " entitlement" + " (see scripts/sign-dev.sh)")
    }
  }
}
