import Foundation
import IOKit.hid
import XCTest

@testable import OpenJoystickDriverKit

final class PhysicalRumbleOutputTests: XCTestCase {
  func testSourceBackedParsersExposeRumble() {
    XCTAssertTrue(hasPhysicalRumble(GIPParser()))
    XCTAssertTrue(hasPhysicalRumble(Xbox360Parser()))
    XCTAssertTrue(hasPhysicalRumble(DS4Parser()))
  }
  func testXpcDescriptionDefaultsRumbleSupportToFalse() {
    let description = XPCDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      parser: "Test",
      connection: "USB",
      serialNumber: nil
    )

    XCTAssertTrue(description.supportsPhysicalRumble == false)
  }
  func testXpcDescriptionDecodesMissingRumbleSupportAsFalse() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "parser": "Test",
        "connection": "USB",
        "serialNumber": null
      }
      """
    let description = try JSONDecoder().decode(XPCDeviceDescription.self, from: Data(json.utf8))

    XCTAssertTrue(description.supportsPhysicalRumble == false)
  }
  func testVirtualParserAcceptsXboxOneRumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 3,
      bytes: [0x0F, 10, 20, 30, 40, 5, 0, 0]
    )

    let expected = VirtualRumbleCommand(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 50
    )
    XCTAssertTrue(command == expected)
  }
  func testVirtualParserAcceptsXboxGIPRumbleReports() {
    let reportIDZeroCommand = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x09, 0x00, 0x12, 0x09, 0x00, 0x0F, 10, 20, 30, 40, 5, 0, 0]
    )
    let reportIDNineCommand = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 9,
      bytes: [0x00, 0x12, 0x09, 0x00, 0x0F, 10, 20, 30, 40, 5, 0, 0]
    )

    let expected = VirtualRumbleCommand(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 50
    )
    XCTAssertTrue(reportIDZeroCommand == expected)
    XCTAssertTrue(reportIDNineCommand == expected)
  }
  func testVirtualParserAcceptsXbox360RumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x00, 0x08, 0x00, 128, 64, 0, 0, 0]
    )

    XCTAssertTrue(command == VirtualRumbleCommand(left: 128, right: 64))
  }
  func testVirtualParserAcceptsOJDCompactRumbleReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [0x4F, 1, 2, 3, 4, 0x2C, 0x01]
    )

    let expected = VirtualRumbleCommand(
      left: 1,
      right: 2,
      leftTrigger: 3,
      rightTrigger: 4,
      durationMs: 300
    )
    XCTAssertTrue(command == expected)
  }
  func testVirtualParserRejectsUnmarkedRelayInputReports() {
    let command = VirtualRumbleOutputReportParser.parse(
      type: kIOHIDReportTypeOutput,
      reportID: 0,
      bytes: [1, 2, 3, 4, 5, 6]
    )

    XCTAssertTrue(command == nil)
  }
  func testDs4PhysicalRumbleReportUsesUSBHIDOutputReport() {
    let report = DS4Parser().physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    XCTAssertTrue(report.reportID == 0x05)
    XCTAssertTrue(report.bytes.count == 32)
    XCTAssertTrue(report.bytes[0] == 0x05)
    XCTAssertTrue(report.bytes[1] == 0x01)
    XCTAssertTrue(report.bytes[4] == 90)
    XCTAssertTrue(report.bytes[5] == 180)
    XCTAssertTrue(report.bytes.dropFirst(6).allSatisfy { $0 == 0 })
  }
  func testDs4PhysicalRumbleReportUsesBluetoothReportAfterBluetoothInput() throws {
    let parser = DS4Parser()
    _ = try parser.parse(
      data: Data([0x11, 0xC0, 0x00, 128, 128, 128, 128, 0x08, 0, 0, 0, 0]
        + [UInt8](repeating: 0, count: 64) + [0x7D, 0x0A, 0x5D, 0x0B])
    )

    let report = parser.physicalRumbleReport(left: 180, right: 90, lt: 255, rt: 64)

    XCTAssertTrue(report.reportID == 0x11)
    XCTAssertTrue(report.bytes.count == 78)
    XCTAssertTrue(report.bytes[0] == 0x11)
    XCTAssertTrue(report.bytes[1] == 0xC0)
    XCTAssertTrue(report.bytes[3] == 0x0F)
    XCTAssertTrue(report.bytes[6] == 90)
    XCTAssertTrue(report.bytes[7] == 180)
    XCTAssertTrue(report.bytes[74...77].contains { $0 != 0 })
  }
  func testDs4PreferredBluetoothParserUsesBluetoothPhysicalRumbleBeforeInput() {
    let report = DS4Parser(prefersBluetooth: true).physicalRumbleReport(
      left: 180,
      right: 90,
      lt: 255,
      rt: 64
    )

    XCTAssertTrue(report.reportID == 0x11)
    XCTAssertTrue(report.bytes.count == 78)
    XCTAssertTrue(report.bytes[6] == 90)
    XCTAssertTrue(report.bytes[7] == 180)
  }

  private func hasPhysicalRumble(_ parser: any InputParser) -> Bool {
    parser is PhysicalRumbleOutput || parser is PhysicalHIDRumbleOutput
  }
}
