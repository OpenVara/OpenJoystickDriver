import Testing

@testable import OpenJoystickDriverKit

@Suite("Xbox One HID Report Format Tests") struct XboxOneHIDReportFormatTests {
  private func format() throws -> HIDDescriptorReportFormat {
    try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
  }

  private func report(buttonBit: Int) throws -> [UInt8] {
    try format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }

  @Test("Xbox One descriptor maps face and shoulder buttons directly")
  func mapsFaceAndShoulderButtonsDirectly() throws {
    let a = try report(buttonBit: 0)
    let rb = try report(buttonBit: 5)

    #expect(a.count == 16)
    #expect(a[0] == 1)
    #expect(a[14] == 0x01)
    #expect(rb[14] == 0x20)
  }

  @Test("Xbox One descriptor parses and packs all primary axes")
  func parsesAndPacksPrimaryAxes() throws {
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

    #expect(full[0] == 1)
    #expect(full[1] == 0xFF)
    #expect(full[2] == 0xFF)
    #expect(full[3] == 0xFF)
    #expect(full[4] == 0xBF)
    #expect(full[5] == 0x00)
    #expect(full[6] == 0x00)
    #expect(full[7] == 0xFF)
    #expect(full[8] == 0x3F)
    #expect(full[9] == 0xFF)
    #expect(full[10] == 0x03)
    #expect(full[11] == 0xFF)
    #expect(full[12] == 0x01)
    #expect(full[13] == 0x00)
    #expect(full[14] == 0x00)
  }

  @Test("Xbox One descriptor keeps raw HID order for stick clicks and menu buttons")
  func mapsStickClicksAndMenuButtonsInRawHIDOrder() throws {
    let view = try report(buttonBit: 9)
    let menu = try report(buttonBit: 8)
    let leftStick = try report(buttonBit: 6)
    let rightStick = try report(buttonBit: 7)

    #expect(leftStick[14] == 0x40)
    #expect(rightStick[14] == 0x80)
    #expect(menu[15] == 0x01)
    #expect(view[15] == 0x02)
  }

  @Test("Xbox One descriptor packs dpad as the hat switch")
  func packsDpadAsHatSwitch() throws {
    let north = try format().buildInputReport(
      from: VirtualGamepadState(hat: .north)
    )
    let east = try format().buildInputReport(
      from: VirtualGamepadState(hat: .east)
    )
    let neutral = try format().buildInputReport(
      from: VirtualGamepadState(hat: .neutral)
    )

    #expect(north[13] == 0x01)
    #expect(east[13] == 0x03)
    #expect(neutral[13] == 0x00)
  }

  @Test("Xbox One descriptor also exposes dpad as digital button usages")
  func packsDpadAsDigitalButtons() throws {
    let north = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north))
    )
    let east = try format().buildInputReport(
      from: VirtualGamepadState(buttons: GamepadHIDDescriptor.dpadButtonBits(for: .east))
    )

    #expect(north[15] == 0x08)
    #expect(east[15] == 0x40)
  }
}
