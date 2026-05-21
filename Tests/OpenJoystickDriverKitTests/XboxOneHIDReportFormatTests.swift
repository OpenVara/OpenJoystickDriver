import XCTest

@testable import OpenJoystickDriverKit

final class XboxOneHIDReportFormatTests: XCTestCase {
  private func format() throws -> HIDDescriptorReportFormat {
    try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
  }

  private func report(buttonBit: Int) throws -> [UInt8] {
    try format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }
  func testMapsFaceAndShoulderButtonsDirectly() throws {
    let a = try report(buttonBit: 0)
    let rb = try report(buttonBit: 5)

    XCTAssertTrue(a.count == 16)
    XCTAssertTrue(a[0] == 1)
    XCTAssertTrue(a[14] == 0x01)
    XCTAssertTrue(rb[14] == 0x20)
  }
  func testParsesAndPacksPrimaryAxes() throws {
    let full = try format().buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: 16_384,
        rightStickX: -32_767,
        rightStickY: -16_384,
        leftTrigger: 32_767,
        rightTrigger: 16_384
      )
    )

    XCTAssertTrue(full[0] == 1)
    XCTAssertTrue(full[1] == 0xFF)
    XCTAssertTrue(full[2] == 0xFF)
    XCTAssertTrue(full[3] == 0xFF)
    XCTAssertTrue(full[4] == 0xBF)
    XCTAssertTrue(full[5] == 0x00)
    XCTAssertTrue(full[6] == 0x00)
    XCTAssertTrue(full[7] == 0xFF)
    XCTAssertTrue(full[8] == 0x3F)
    XCTAssertTrue(full[9] == 0xFF)
    XCTAssertTrue(full[10] == 0x03)
    XCTAssertTrue(full[11] == 0xFF)
    XCTAssertTrue(full[12] == 0x01)
    XCTAssertTrue(full[13] == 0x00)
    XCTAssertTrue(full[14] == 0x00)
  }
  func testMapsStickClicksAndMenuButtonsInRawHIDOrder() throws {
    let view = try report(buttonBit: 9)
    let menu = try report(buttonBit: 8)
    let leftStick = try report(buttonBit: 6)
    let rightStick = try report(buttonBit: 7)

    XCTAssertTrue(leftStick[14] == 0x40)
    XCTAssertTrue(rightStick[14] == 0x80)
    XCTAssertTrue(menu[15] == 0x01)
    XCTAssertTrue(view[15] == 0x02)
  }
  func testPacksDpadAsHatSwitch() throws {
    let north = try format().buildInputReport(
      from: VirtualGamepadState(hat: .north)
    )
    let east = try format().buildInputReport(
      from: VirtualGamepadState(hat: .east)
    )
    let neutral = try format().buildInputReport(
      from: VirtualGamepadState(hat: .neutral)
    )

    XCTAssertTrue(north[13] == 0x01)
    XCTAssertTrue(east[13] == 0x03)
    XCTAssertTrue(neutral[13] == 0x00)
  }
  func testPacksDpadAsDigitalButtons() throws {
    let north = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north))
    )
    let east = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .east))
    )

    XCTAssertTrue(north[15] == 0x08)
    XCTAssertTrue(east[15] == 0x40)
  }
}
