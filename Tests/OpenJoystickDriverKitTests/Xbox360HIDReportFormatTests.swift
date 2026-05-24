import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct Xbox360HIDReportFormatTests {
  private func format() -> Xbox360XUSBDirectInputReportFormat {
    Xbox360XUSBDirectInputReportFormat()
  }

  private func report(buttonBit: Int) -> [UInt8] {
    format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }
  @Test
  func testExposesReportShape() throws {
    let f = format()
    let parsed = try HIDDescriptorReportFormat(descriptor: f.descriptor)

    #expect(f.inputReportID == nil)
    #expect(f.inputReportPayloadSize == 13)
    #expect(f.buildInputReport(from: VirtualGamepadState()).count == 13)
    #expect(parsed.inputReportID == nil)
    #expect(parsed.inputReportPayloadSize == 13)
  }
  @Test
  func testMapsFaceAndShoulderButtons() {
    let a = report(buttonBit: 0)
    let y = report(buttonBit: 3)
    let lb = report(buttonBit: 4)
    let rb = report(buttonBit: 5)

    #expect(a[0] == 0x01)
    #expect(y[0] == 0x08)
    #expect(lb[0] == 0x10)
    #expect(rb[0] == 0x20)
  }
  @Test
  func testMapsControlButtons() {
    let leftStick = report(buttonBit: 6)
    let rightStick = report(buttonBit: 7)
    let menu = report(buttonBit: 8)
    let view = report(buttonBit: 9)

    #expect(view[0] == 0x40)
    #expect(menu[0] == 0x80)
    #expect(leftStick[1] == 0x01)
    #expect(rightStick[1] == 0x02)
  }
  @Test
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

    #expect(north[0] == 0x00)
    #expect(north[2] == 0x01)
    #expect(east[0] == 0x00)
    #expect(east[2] == 0x03)
    #expect(neutral[2] == 0x00)
  }
  @Test
  func testPacksSticks() {
    let full = format().buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: -32_767,
        rightStickX: 16_384,
        rightStickY: -16_384
      )
    )

    #expect(full[3] == 0xFF)
    #expect(full[4] == 0x7F)
    #expect(full[5] == 0x01)
    #expect(full[6] == 0x80)
    #expect(full[9] == 0x00)
    #expect(full[10] == 0x40)
    #expect(full[11] == 0x00)
    #expect(full[12] == 0xC0)
  }
  @Test
  func testCombinesTriggersOnZ() {
    let neutral = format().buildInputReport(from: VirtualGamepadState())
    let left = format().buildInputReport(from: VirtualGamepadState(leftTrigger: 32_767))
    let right = format().buildInputReport(from: VirtualGamepadState(rightTrigger: 32_767))
    let both = format().buildInputReport(
      from: VirtualGamepadState(leftTrigger: 16_384, rightTrigger: 16_384)
    )

    #expect(neutral[7] == 0x00)
    #expect(neutral[8] == 0x00)
    #expect(left[7] == 0xFF)
    #expect(left[8] == 0x7F)
    #expect(right[7] == 0x01)
    #expect(right[8] == 0x80)
    #expect(both[7] == 0x00)
    #expect(both[8] == 0x00)
  }
  @Test
  func testIgnoresGuide() {
    let guide = report(buttonBit: 10)

    #expect(guide[0] == 0x00)
    #expect(guide[1] == 0x00)
  }
}


struct Xbox360MacHIDReportFormatTests {
  private func format() -> Xbox360MacHIDReportFormat { Xbox360MacHIDReportFormat() }
  @Test
  func testSelectsTopLevelUsage() {
    let joystick = Xbox360MacHIDReportFormat()
    let gamePad = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))

    #expect(joystick.descriptor[3] == UInt8(kHIDUsage_GD_Joystick))
    #expect(gamePad.descriptor[3] == UInt8(kHIDUsage_GD_GamePad))
    #expect(Array(joystick.descriptor[4...]) == Array(gamePad.descriptor[4...]))
  }
  @Test
  func testExposesIndependentTriggers() throws {
    let f = format()
    let parsed = try HIDDescriptorReportFormat(descriptor: f.descriptor)
    let neutral = f.buildInputReport(from: VirtualGamepadState())
    let left = f.buildInputReport(from: VirtualGamepadState(leftTrigger: 32_767))
    let right = f.buildInputReport(from: VirtualGamepadState(rightTrigger: 32_767))

    #expect(f.inputReportID == nil)
    #expect(f.inputReportPayloadSize == 14)
    #expect(parsed.inputReportID == nil)
    #expect(parsed.inputReportPayloadSize == 14)
    #expect(neutral[4] == 0)
    #expect(neutral[5] == 0)
    #expect(left[4] == 255)
    #expect(left[5] == 0)
    #expect(right[4] == 0)
    #expect(right[5] == 255)
  }
  @Test
  func testStatePacketCarriesXbox360Header() {
    let neutral = format().buildInputReport(from: VirtualGamepadState())

    #expect(neutral[0] == 0x00)
    #expect(neutral[1] == 0x14)
  }
  @Test
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

    #expect(Array(descriptorPacked.dropFirst(2)) == Array(bespokePacked.dropFirst(2)))
  }
  @Test
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

    #expect(report[2] == 0xF1)
    #expect(report[3] == 0xF4)
  }
  @Test
  func testShoulderReleaseClearsHighButtonByte() {
    let pressed = format().buildInputReport(
      from: VirtualGamepadState(
        buttons: (1 << GamepadHIDDescriptor.ButtonBit.leftBumper.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.rightBumper.rawValue)
      )
    )
    let released = format().buildInputReport(from: VirtualGamepadState())

    #expect(pressed[3] == 0x03)
    #expect(released[3] == 0x00)
  }
}
