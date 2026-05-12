import Foundation

/// SDL/PCSX2 user-space HID descriptor for the OJD-owned compatibility identity.
///
/// Report layout (14 bytes total):
///   Bytes 0-1  : Button bitmask, buttons 1-16
///   Bytes 2-3  : Left Stick X, Int16 LE
///   Bytes 4-5  : Left Stick Y, Int16 LE
///   Bytes 6-7  : Left Trigger, Int16 LE, zero idle
///   Bytes 8-9  : Right Stick X, Int16 LE
///   Bytes 10-11: Right Stick Y, Int16 LE
///   Bytes 12-13: Right Trigger, Int16 LE, zero idle
public enum SDLGamepadHIDDescriptor {
  public static let descriptor: [UInt8] = [
    0x05, 0x01,
    0x09, 0x05,
    0xA1, 0x01,
    0xA1, 0x00,

    // Buttons 1-16. D-pad directions are buttons 12-15.
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x10,
    0x15, 0x00,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x10,
    0x81, 0x02,

    // Axes: X, Y, Z(LT), Rx, Ry, Rz(RT), all signed so idle is zero.
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x09, 0x32,
    0x09, 0x33,
    0x09, 0x34,
    0x09, 0x35,
    0x16, 0x01, 0x80,
    0x26, 0xFF, 0x7F,
    0x75, 0x10,
    0x95, 0x06,
    0x81, 0x02,

    // 14-byte output report mirrors the input payload for daemon -> dext relay.
    0x09, 0x01,
    0x15, 0x00,
    0x26, 0xFF, 0x00,
    0x75, 0x08,
    0x95, 0x0E,
    0x91, 0x02,

    0xC0,
    0xC0,
  ]

  public static let reportSize = 14
}
