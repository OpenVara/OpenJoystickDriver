import Testing

@testable import OpenJoystickDriverKit

@Suite("Xbox 360 HID Report Format Tests") struct Xbox360HIDReportFormatTests {
  private func format() -> Xbox360XUSBDirectInputReportFormat {
    Xbox360XUSBDirectInputReportFormat()
  }

  private func report(buttonBit: Int) -> [UInt8] {
    format().buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit)))
  }

  @Test("Xbox 360 XUSB DirectInput format is a 13-byte report with no report ID")
  func exposesReportShape() throws {
    let f = format()
    let parsed = try HIDDescriptorReportFormat(descriptor: f.descriptor)

    #expect(f.inputReportID == nil)
    #expect(f.inputReportPayloadSize == 13)
    #expect(f.buildInputReport(from: VirtualGamepadState()).count == 13)
    #expect(parsed.inputReportID == nil)
    #expect(parsed.inputReportPayloadSize == 13)
  }

  @Test("Xbox 360 XUSB DirectInput maps face and shoulder buttons")
  func mapsFaceAndShoulderButtons() {
    let a = report(buttonBit: 0)
    let y = report(buttonBit: 3)
    let lb = report(buttonBit: 4)
    let rb = report(buttonBit: 5)

    #expect(a[0] == 0x01)
    #expect(y[0] == 0x08)
    #expect(lb[0] == 0x10)
    #expect(rb[0] == 0x20)
  }

  @Test("Xbox 360 XUSB DirectInput maps menu, view, and stick clicks")
  func mapsControlButtons() {
    let leftStick = report(buttonBit: 6)
    let rightStick = report(buttonBit: 7)
    let menu = report(buttonBit: 8)
    let view = report(buttonBit: 9)

    #expect(view[0] == 0x40)
    #expect(menu[0] == 0x80)
    #expect(leftStick[1] == 0x01)
    #expect(rightStick[1] == 0x02)
  }

  @Test("Xbox 360 XUSB DirectInput exposes dpad as hat only")
  func mapsDpadAsHatOnly() {
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

  @Test("Xbox 360 XUSB DirectInput packs sticks")
  func packsSticks() {
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

  @Test("Xbox 360 XUSB DirectInput combines triggers on Z")
  func combinesTriggersOnZ() {
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

  @Test("Xbox 360 XUSB DirectInput does not expose guide")
  func ignoresGuide() {
    let guide = report(buttonBit: 10)

    #expect(guide[0] == 0x00)
    #expect(guide[1] == 0x00)
  }
}
