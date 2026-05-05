import Foundation

/// HID surface for Xbox 360 XUSB controllers as seen by legacy DirectInput consumers.
///
/// Microsoft documents that XUSB controllers expose a HID-compatible DirectInput
/// surface for older applications. This is still HID, not true XInput/XUSB:
/// macOS IOHIDUserDevice cannot publish Windows XUSB interfaces or XInput IOCTLs.
///
/// Report layout (13 bytes):
///   Bytes 0-1  : 10 digital buttons, Button 1 = A through Button 10 = R3
///   Byte  2    : hat switch, 1-8 directions, 0 neutral
///   Bytes 3-4  : Left stick X, Int16 LE
///   Bytes 5-6  : Left stick Y, Int16 LE
///   Bytes 7-8  : Combined trigger Z axis, Int16 LE (LT positive, RT negative)
///   Bytes 9-10 : Right stick X, Int16 LE
///   Bytes 11-12: Right stick Y, Int16 LE
public enum Xbox360XUSBDirectInputHIDDescriptor {
  public static let descriptor: [UInt8] = [
    0x05, 0x01,  // Usage Page: Generic Desktop
    0x09, 0x05,  // Usage: Game Pad
    0xA1, 0x01,  // Collection: Application

    // Buttons 1-10: A, B, X, Y, LB, RB, Back, Start, L3, R3.
    0x05, 0x09,  // Usage Page: Button
    0x19, 0x01,  // Usage Minimum: 1
    0x29, 0x0A,  // Usage Maximum: 10
    0x15, 0x00,  // Logical Minimum: 0
    0x25, 0x01,  // Logical Maximum: 1
    0x75, 0x01,  // Report Size: 1
    0x95, 0x0A,  // Report Count: 10
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // Pad buttons to 16 bits.
    0x75, 0x06,
    0x95, 0x01,
    0x81, 0x03,

    // D-pad as a hat switch. DirectInput does not expose it as four buttons.
    0x05, 0x01,  // Usage Page: Generic Desktop
    0x09, 0x39,  // Usage: Hat Switch
    0x15, 0x01,  // Logical Minimum: 1
    0x25, 0x08,  // Logical Maximum: 8
    0x35, 0x00,  // Physical Minimum: 0
    0x46, 0x3B, 0x01,  // Physical Maximum: 315
    0x66, 0x14, 0x00,  // Unit: degrees
    0x75, 0x04,
    0x95, 0x01,
    0x81, 0x42,  // Input: Data, Variable, Absolute, Null State

    // Pad hat to a full byte.
    0x75, 0x04,
    0x95, 0x01,
    0x81, 0x03,

    // Axes: X, Y, combined-trigger Z, Rx, Ry.
    0x05, 0x01,
    0x09, 0x30,  // X
    0x09, 0x31,  // Y
    0x09, 0x32,  // Z
    0x09, 0x33,  // Rx
    0x09, 0x34,  // Ry
    0x16, 0x00, 0x80,  // Logical Minimum: -32768
    0x26, 0xFF, 0x7F,  // Logical Maximum: 32767
    0x75, 0x10,
    0x95, 0x05,
    0x81, 0x02,

    0xC0,
  ]
}

/// Report formatter for Microsoft XUSB DirectInput compatibility.
public struct Xbox360XUSBDirectInputReportFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = Xbox360XUSBDirectInputHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = 13
  public let inputReportID: UInt8? = nil

  public init() {}

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: inputReportPayloadSize)

    let buttons = directInputButtons(from: state.buttons)
    r[0] = UInt8(buttons & 0xFF)
    r[1] = UInt8((buttons >> 8) & 0x03)
    r[2] = state.hat.rawValue & 0x0F

    write(state.leftStickX, to: &r, at: 3)
    write(state.leftStickY, to: &r, at: 5)
    write(combinedTriggerAxis(left: state.leftTrigger, right: state.rightTrigger), to: &r, at: 7)
    write(state.rightStickX, to: &r, at: 9)
    write(state.rightStickY, to: &r, at: 11)
    return r
  }

  private func directInputButtons(from normalized: UInt32) -> UInt16 {
    var out: UInt16 = 0

    func set(_ sourceBit: Int, _ directInputBit: Int) {
      if ((normalized >> UInt32(sourceBit)) & 1) != 0 {
        out |= UInt16(1 << directInputBit)
      }
    }

    set(0, 0)  // A
    set(1, 1)  // B
    set(2, 2)  // X
    set(3, 3)  // Y
    set(4, 4)  // LB
    set(5, 5)  // RB
    set(9, 6)  // Back/View
    set(8, 7)  // Start/Menu
    set(6, 8)  // L3
    set(7, 9)  // R3
    return out
  }

  private func combinedTriggerAxis(left: Int16, right: Int16) -> Int16 {
    let leftValue = Int(left)
    let rightValue = Int(right)
    let combined = leftValue - rightValue
    return Int16(max(Int(Int16.min), min(Int(Int16.max), combined)))
  }

  private func write(_ value: Int16, to report: inout [UInt8], at offset: Int) {
    let b = value.littleEndianBytes
    report[offset] = b.0
    report[offset + 1] = b.1
  }
}
