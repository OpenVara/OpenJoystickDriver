import Foundation

/// HID report descriptor for the macOS Xbox 360 wired-controller shape.
///
/// This is the IOHIDDevice-style gamepad surface used by the historical macOS
/// Xbox 360 driver family, not the Windows XUSB USB configuration used by
/// ViGEmBus. IOHIDUserDevice needs a HID report descriptor, so the XUSB
/// descriptor is reference material only for this backend.
///
/// Report layout (14 bytes):
///   Bytes 0-1: counted-buffer header fields exposed as constant inputs
///   Bytes 2-3: 16 digital buttons in the macOS 360 HID element order
///              dpad, start/menu, back/view, stick clicks, shoulders, guide,
///              then A/B/X/Y; this matches the XINPUT_GAMEPAD bitmask order.
///   Byte  4  : Left trigger, 0...255
///   Byte  5  : Right trigger, 0...255
///   Bytes 6-7: Left stick X, Int16 LE
///   Bytes 8-9: Left stick Y, Int16 LE
///   Bytes 10-11: Right stick X, Int16 LE
///   Bytes 12-13: Right stick Y, Int16 LE
///   Output: 8-byte Xbox 360 rumble packet `[0x00, 0x08, 0x00, left, right, 0, 0, 0]`
///
/// The default top-level usage is Joystick rather than Game Pad. SDL still
/// treats both usages as controllers, while macOS GameController's synthetic
/// controller plugin can synchronously claim and hang on a `045E:028E` Game Pad
/// during SDL HIDAPI initialization. The Apple GameController compatibility
/// identity can request a Game Pad descriptor when SDL HIDAPI is disabled or
/// patched to avoid that claim path.
public enum Xbox360MacHIDDescriptor {
  public static let descriptor: [UInt8] = descriptor(topLevelUsage: UInt8(kHIDUsage_GD_Joystick))

  public static func descriptor(topLevelUsage: UInt8) -> [UInt8] {
    var descriptor = baseDescriptor
    descriptor[3] = topLevelUsage
    return descriptor
  }

  private static let baseDescriptor: [UInt8] = [
    0x05, 0x01,  // Usage Page: Generic Desktop
    0x09, 0x04,  // Usage: Joystick
    0xA1, 0x01,  // Collection: Application
    0x05, 0x01,  //   Usage Page: Generic Desktop
    0x09, 0x3A,  //   Usage: Counted Buffer
    0xA1, 0x02,  //   Collection: Logical

    // Two constant header bytes.
    0x75, 0x08,
    0x95, 0x02,
    0x05, 0x01,
    0x09, 0x3F,
    0x09, 0x3B,
    0x81, 0x01,

    // D-pad button usages first, in the macOS 360 HID byte order.
    0x75, 0x01,
    0x15, 0x00,
    0x25, 0x01,
    0x35, 0x00,
    0x45, 0x01,
    0x95, 0x04,
    0x05, 0x09,
    0x19, 0x0C,
    0x29, 0x0F,
    0x81, 0x02,

    // Menu/View and stick clicks.
    0x75, 0x01,
    0x15, 0x00,
    0x25, 0x01,
    0x35, 0x00,
    0x45, 0x01,
    0x95, 0x04,
    0x05, 0x09,
    0x09, 0x09,
    0x09, 0x0A,
    0x09, 0x07,
    0x09, 0x08,
    0x81, 0x02,

    // Shoulders and guide.
    0x75, 0x01,
    0x15, 0x00,
    0x25, 0x01,
    0x35, 0x00,
    0x45, 0x01,
    0x95, 0x03,
    0x05, 0x09,
    0x09, 0x05,
    0x09, 0x06,
    0x09, 0x0B,
    0x81, 0x02,

    // One bit of padding.
    0x75, 0x01,
    0x95, 0x01,
    0x81, 0x01,

    // Face buttons.
    0x75, 0x01,
    0x15, 0x00,
    0x25, 0x01,
    0x35, 0x00,
    0x45, 0x01,
    0x95, 0x04,
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x04,
    0x81, 0x02,

    // Analog triggers: Z, Rz.
    0x75, 0x08,
    0x15, 0x00,
    0x26, 0xFF, 0x00,
    0x35, 0x00,
    0x46, 0xFF, 0x00,
    0x95, 0x02,
    0x05, 0x01,
    0x09, 0x32,
    0x09, 0x35,
    0x81, 0x02,

    // Left stick: X/Y.
    0x75, 0x10,
    0x16, 0x00, 0x80,
    0x26, 0xFF, 0x7F,
    0x36, 0x00, 0x80,
    0x46, 0xFF, 0x7F,
    0x05, 0x01,
    0x09, 0x01,
    0xA1, 0x00,
    0x95, 0x02,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x81, 0x02,
    0xC0,

    // Right stick: Rx/Ry.
    0x05, 0x01,
    0x09, 0x01,
    0xA1, 0x00,
    0x95, 0x02,
    0x05, 0x01,
    0x09, 0x33,
    0x09, 0x34,
    0x81, 0x02,
    0xC0,

    // Xbox 360 rumble output report. SDL HIDAPI and other Xbox-style callers
    // commonly send `[0x00, 0x08, 0x00, left, right, 0, 0, 0]`.
    0x09, 0x01,
    0x15, 0x00,
    0x26, 0xFF, 0x00,
    0x75, 0x08,
    0x95, 0x08,
    0x91, 0x02,

    0xC0,
    0xC0,
  ]
}

public struct Xbox360MacHIDReportFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8]
  public let topLevelUsage: UInt8
  public let inputReportPayloadSize: Int = 14
  public let inputReportID: UInt8? = nil
  public let outputReportPayloadSize: Int? = 8
  public let outputReportID: UInt8? = nil

  public init(topLevelUsage: UInt8 = UInt8(kHIDUsage_GD_Joystick)) {
    self.topLevelUsage = topLevelUsage
    self.descriptor = Xbox360MacHIDDescriptor.descriptor(topLevelUsage: topLevelUsage)
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: inputReportPayloadSize)
    let mask = xinputButtonMask(from: state.buttons)
    r[2] = UInt8(mask & 0xFF)
    r[3] = UInt8((mask >> 8) & 0xFF)
    r[4] = triggerByte(state.leftTrigger)
    r[5] = triggerByte(state.rightTrigger)
    write(state.leftStickX, to: &r, at: 6)
    write(state.leftStickY, to: &r, at: 8)
    write(state.rightStickX, to: &r, at: 10)
    write(state.rightStickY, to: &r, at: 12)
    return r
  }

  private func xinputButtonMask(from normalized: UInt32) -> UInt16 {
    var out: UInt16 = 0

    func set(_ sourceBit: Int, _ xinputBit: Int) {
      if ((normalized >> UInt32(sourceBit)) & 1) != 0 {
        out |= UInt16(1 << xinputBit)
      }
    }

    set(11, 0)
    set(12, 1)
    set(13, 2)
    set(14, 3)
    set(8, 4)
    set(9, 5)
    set(6, 6)
    set(7, 7)
    set(4, 8)
    set(5, 9)
    set(10, 10)
    set(0, 12)
    set(1, 13)
    set(2, 14)
    set(3, 15)
    return out
  }

  private func triggerByte(_ value: Int16) -> UInt8 {
    let clamped = max(0, min(32_767, Int(value)))
    return UInt8(clamped * 255 / 32_767)
  }

  private func write(_ value: Int16, to report: inout [UInt8], at offset: Int) {
    let b = value.littleEndianBytes
    report[offset] = b.0
    report[offset + 1] = b.1
  }
}
