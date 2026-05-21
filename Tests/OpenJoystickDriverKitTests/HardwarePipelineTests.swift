import Foundation
import SwiftUSB
import XCTest

@testable import OpenJoystickDriverKit

private let gamesirVID: UInt16 = 13623  // 0x3537
private let gamesirPID: UInt16 = 4112  // 0x1010
private let hardwareTestsEnabled =
  ProcessInfo.processInfo.environment["OJD_HARDWARE_TESTS"] == "1"
private let hardwareSkipMessage =
  "[HardwareTest] Skipping USB hardware test; set OJD_HARDWARE_TESTS=1 to require it."

final class HardwarePipelineTests: XCTestCase {
  /// Shared USBContext for enabled hardware tests.
  ///
  /// Kept lazy so the default skipped hardware path does not touch libusb at
  /// module load time.
  private static let sharedContext: USBContext? = try? USBContext()

  func testDeviceEnumeration() async throws {
    guard hardwareTestsEnabled else {
      throw XCTSkip(hardwareSkipMessage)
    }
    guard let context = Self.sharedContext else {
      XCTFail("Failed to create USBContext")
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
    XCTAssertTrue(found, "Gamesir G7 SE should be enumerable via SwiftUSB")
  }
  func testGipHandshakeAndInput() async throws {
    guard hardwareTestsEnabled else {
      throw XCTSkip(hardwareSkipMessage)
    }
    guard let context = Self.sharedContext else {
      XCTFail("Failed to create USBContext")
      return
    }
    guard let device = await context.findDevice(vendorId: gamesirVID, productId: gamesirPID) else {
      XCTFail("Gamesir G7 SE not found - is it connected?")
      return
    }

    let handle: USBDeviceHandle
    do { handle = try device.open() } catch let error as USBError where error.isAccessDenied {
      throw XCTSkip(
        "[HardwareTest] USB access denied - skipping handshake test (needs root or entitlements)"
      )
    }
    do { try handle.claimInterface(0) } catch let error as USBError where error.isAccessDenied {
      throw XCTSkip("[HardwareTest] Cannot claim interface - skipping (access denied)")
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

    if let parseError { XCTFail("Parse/USB error: \(parseError)") }
    XCTAssertTrue(gotReport, "Should receive at least 1 input report after handshake")
  }
  func testParserRegistryDispatch() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID)
    let parser = registry.parser(for: identifier)
    XCTAssertTrue(parser is GIPParser, "G7 SE should get GIPParser, got \(type(of: parser))")
  }
  func testDeviceIdentifierMatching() {
    let id1 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "ABC123")
    let id2 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "XYZ789")
    let id3 = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    XCTAssertTrue(id1.modelMatches(id2))
    XCTAssertTrue(!id1.modelMatches(id3))
    XCTAssertTrue(!id1.exactlyMatches(id2))
  }
}
