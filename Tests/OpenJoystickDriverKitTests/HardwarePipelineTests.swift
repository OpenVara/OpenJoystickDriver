import Foundation
import SwiftUSB
import Testing

@testable import OpenJoystickDriverKit

private let gamesirVID: UInt16 = 13623  // 0x3537
private let gamesirPID: UInt16 = 4112  // 0x1010

/// Shared USBContext for all hardware tests.
/// Avoids creating/destroying multiple libusb contexts
/// which can cause crashes due to event loop thread races.
private let sharedContext: USBContext? = try? USBContext()

@Suite("Hardware Pipeline Tests", .serialized) struct HardwarePipelineTests {

  @Test("Gamesir G7 SE is enumerated by SwiftUSB") func deviceEnumeration() async throws {
    guard let context = sharedContext else {
      Issue.record("Failed to create USBContext")
      return
    }
    var found = false
    let stream = context.findDevices(vendorId: gamesirVID, productId: gamesirPID, findAll: false)
    for await device in stream where device.idVendor == gamesirVID && device.idProduct == gamesirPID
    {
      found = true
      print(
        "[HardwareTest] Found G7 SE:" + " bus=\(device.bus)" + " addr=\(device.address)"
          + " class=\(device.bDeviceClass)"
      )
      break
    }
    #expect(found, "Gamesir G7 SE should be enumerable via SwiftUSB")
  }

  @Test("GIP handshake and single input report read") func gipHandshakeAndInput() async throws {
    guard let context = sharedContext else {
      Issue.record("Failed to create USBContext")
      return
    }
    guard let device = await context.findDevice(vendorId: gamesirVID, productId: gamesirPID) else {
      Issue.record("Gamesir G7 SE not found - is it connected?")
      return
    }

    let handle: USBDeviceHandle
    do { handle = try device.open() } catch let error as USBError where error.isAccessDenied {
      print(
        "[HardwareTest] USB access denied" + " - skipping handshake test"
          + " (needs root or entitlements)"
      )
      return
    }
    do { try handle.claimInterface(0) } catch let error as USBError where error.isAccessDenied {
      print("[HardwareTest] Cannot claim interface" + " - skipping (access denied)")
      return
    }

    let parser = GIPParser()

    try await parser.performHandshake(handle: handle)
    print("[HardwareTest] Handshake sent" + " - G7 SE LED should be on")

    var gotReport = false
    var parseError: (any Error)?

    for _ in 0..<5 {
      do {
        let data = try handle.readInterrupt(endpoint: 0x82, length: 64, timeout: 1000)
        print("[HardwareTest] Report bytes:" + " \(Array(data).prefix(8))")
        let events = try parser.parse(data: Data(data))
        print("[HardwareTest] Parsed \(events.count) events")
        gotReport = true
        break
      } catch let error as USBError where error.isTimeout { continue } catch {
        parseError = error
        break
      }
    }

    try? handle.releaseInterface(0)

    if let parseError { Issue.record("Parse/USB error: \(parseError)") }
    #expect(gotReport, "Should receive at least 1 input report after handshake")
  }

  @Test("ParserRegistry returns GIPParser for G7 SE") func parserRegistryDispatch() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID)
    let parser = registry.parser(for: identifier)
    #expect(parser is GIPParser, "G7 SE should get GIPParser, got \(type(of: parser))")
  }

  @Test("DeviceIdentifier correctly identifies G7 SE model") func deviceIdentifierMatching() {
    let id1 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "ABC123")
    let id2 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "XYZ789")
    let id3 = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    #expect(id1.modelMatches(id2))
    #expect(!id1.modelMatches(id3))
    #expect(!id1.exactlyMatches(id2))
  }
}
