import XCTest

@testable import OpenJoystickDriverKit

final class Xbox360HIDReportFormatTests: XCTestCase {
  private func format() -> Xbox360XUSBDirectInputReportFormat {
    Xbox360XUSBDirectInputReportFormat()
  }

  private func report(buttonBit: Int) -> [UInt8] {
    format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }
  func testExposesReportShape() throws {
    let f = format()
    let parsed = try HIDDescriptorReportFormat(descriptor: f.descriptor)

    XCTAssertTrue(f.inputReportID == nil)
    XCTAssertTrue(f.inputReportPayloadSize == 13)
    XCTAssertTrue(f.buildInputReport(from: VirtualGamepadState()).count == 13)
    XCTAssertTrue(parsed.inputReportID == nil)
    XCTAssertTrue(parsed.inputReportPayloadSize == 13)
  }
  func testMapsFaceAndShoulderButtons() {
    let a = report(buttonBit: 0)
    let y = report(buttonBit: 3)
    let lb = report(buttonBit: 4)
    let rb = report(buttonBit: 5)

    XCTAssertTrue(a[0] == 0x01)
    XCTAssertTrue(y[0] == 0x08)
    XCTAssertTrue(lb[0] == 0x10)
    XCTAssertTrue(rb[0] == 0x20)
  }
  func testMapsControlButtons() {
    let leftStick = report(buttonBit: 6)
    let rightStick = report(buttonBit: 7)
    let menu = report(buttonBit: 8)
    let view = report(buttonBit: 9)

    XCTAssertTrue(view[0] == 0x40)
    XCTAssertTrue(menu[0] == 0x80)
    XCTAssertTrue(leftStick[1] == 0x01)
    XCTAssertTrue(rightStick[1] == 0x02)
  }
  func testMapsDpadAsHatOnly() {
    let north = format().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north),
        hat: .north
      )
    )
    let east = format().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .east),
        hat: .east
      )
    )
    let neutral = format().buildInputReport(from: VirtualGamepadState())

    XCTAssertTrue(north[0] == 0x00)
    XCTAssertTrue(north[2] == 0x01)
    XCTAssertTrue(east[0] == 0x00)
    XCTAssertTrue(east[2] == 0x03)
    XCTAssertTrue(neutral[2] == 0x00)
  }
  func testPacksSticks() {
    let full = format().buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: -32_767,
        rightStickX: 16_384,
        rightStickY: -16_384
      )
    )

    XCTAssertTrue(full[3] == 0xFF)
    XCTAssertTrue(full[4] == 0x7F)
    XCTAssertTrue(full[5] == 0x01)
    XCTAssertTrue(full[6] == 0x80)
    XCTAssertTrue(full[9] == 0x00)
    XCTAssertTrue(full[10] == 0x40)
    XCTAssertTrue(full[11] == 0x00)
    XCTAssertTrue(full[12] == 0xC0)
  }
  func testCombinesTriggersOnZ() {
    let neutral = format().buildInputReport(from: VirtualGamepadState())
    let left = format().buildInputReport(from: VirtualGamepadState(leftTrigger: 32_767))
    let right = format().buildInputReport(from: VirtualGamepadState(rightTrigger: 32_767))
    let both = format().buildInputReport(
      from: VirtualGamepadState(leftTrigger: 16_384, rightTrigger: 16_384)
    )

    XCTAssertTrue(neutral[7] == 0x00)
    XCTAssertTrue(neutral[8] == 0x00)
    XCTAssertTrue(left[7] == 0xFF)
    XCTAssertTrue(left[8] == 0x7F)
    XCTAssertTrue(right[7] == 0x01)
    XCTAssertTrue(right[8] == 0x80)
    XCTAssertTrue(both[7] == 0x00)
    XCTAssertTrue(both[8] == 0x00)
  }
  func testIgnoresGuide() {
    let guide = report(buttonBit: 10)

    XCTAssertTrue(guide[0] == 0x00)
    XCTAssertTrue(guide[1] == 0x00)
  }
}


final class Xbox360MacHIDReportFormatTests: XCTestCase {
  private func format() -> Xbox360MacHIDReportFormat { Xbox360MacHIDReportFormat() }
  func testSelectsTopLevelUsage() {
    let joystick = Xbox360MacHIDReportFormat()
    let gamePad = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))

    XCTAssertTrue(joystick.descriptor[3] == UInt8(kHIDUsage_GD_Joystick))
    XCTAssertTrue(gamePad.descriptor[3] == UInt8(kHIDUsage_GD_GamePad))
    XCTAssertTrue(Array(joystick.descriptor[4...]) == Array(gamePad.descriptor[4...]))
  }
  func testExposesIndependentTriggers() throws {
    let f = format()
    let parsed = try HIDDescriptorReportFormat(descriptor: f.descriptor)
    let neutral = f.buildInputReport(from: VirtualGamepadState())
    let left = f.buildInputReport(from: VirtualGamepadState(leftTrigger: 32_767))
    let right = f.buildInputReport(from: VirtualGamepadState(rightTrigger: 32_767))

    XCTAssertTrue(f.inputReportID == nil)
    XCTAssertTrue(f.inputReportPayloadSize == 14)
    XCTAssertTrue(parsed.inputReportID == nil)
    XCTAssertTrue(parsed.inputReportPayloadSize == 14)
    XCTAssertTrue(neutral[4] == 0)
    XCTAssertTrue(neutral[5] == 0)
    XCTAssertTrue(left[4] == 255)
    XCTAssertTrue(left[5] == 0)
    XCTAssertTrue(right[4] == 0)
    XCTAssertTrue(right[5] == 255)
  }
  func testDescriptorFieldsMatchReportPacking() throws {
    let state = VirtualGamepadState(
      buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
        | (1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue)
        | (1 << GamepadHIDDescriptor.ButtonBit.a.rawValue),
      leftStickX: 12_345,
      leftStickY: -12_345,
      rightStickX: 23_456,
      rightStickY: -23_456,
      leftTrigger: 32_767,
      rightTrigger: 16_384
    )

    let descriptorPacked = try HIDDescriptorReportFormat(descriptor: format().descriptor)
      .buildInputReport(from: state)
    let bespokePacked = format().buildInputReport(from: state)

    XCTAssertTrue(descriptorPacked == bespokePacked)
  }
  func testMapsXInputButtonOrder() {
    let buttons = GamepadHIDDescriptor.dpadButtonBits(for: .north)
      | (1 << GamepadHIDDescriptor.ButtonBit.start.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.back.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.leftStick.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.rightStick.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.a.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.b.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.x.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.y.rawValue)
    let report = format().buildInputReport(from: VirtualGamepadState(buttons: buttons))

    XCTAssertTrue(report[2] == 0xF1)
    XCTAssertTrue(report[3] == 0xF4)
  }
}
