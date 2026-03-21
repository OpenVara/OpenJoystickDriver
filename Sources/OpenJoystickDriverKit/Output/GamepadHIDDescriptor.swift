import Foundation

/// Standard 13-byte USB HID gamepad report descriptor and report layout.
///
/// Produces a virtual HID device recognised by SDL3, GCController, and any
/// IOKit HID consumer as a generic gamepad. No entitlements are required
/// beyond those already held by the daemon.
///
/// Report layout (13 bytes total):
///   Bytes 0–1  : Button bitmask, buttons 1–16 (LSB = button 1)
///   Bytes 2–3  : Left Stick X  (Int16 LE, –32767…32767)
///   Bytes 4–5  : Left Stick Y  (Int16 LE, –32767…32767)
///   Bytes 6–7  : Right Stick X (Int16 LE, –32767…32767)
///   Bytes 8–9  : Right Stick Y (Int16 LE, –32767…32767)
///   Byte  10   : Left Trigger  (UInt8, 0…255)
///   Byte  11   : Right Trigger (UInt8, 0…255)
///   Byte  12   : Hat switch (low nibble, 0–7 = direction, 8 = neutral) + 4-bit pad
public enum GamepadHIDDescriptor {
  // MARK: - Report descriptor bytes

  // Indentation reflects HID descriptor hierarchy — intentionally not vertically aligned.
  /// Raw HID report descriptor that describes the virtual gamepad layout.
  public static let descriptor: [UInt8] = [
    // ----- Usage Page: Generic Desktop -----
    0x05, 0x01,
    // Usage: Gamepad
    0x09, 0x05,
    // Collection: Application
    0xA1, 0x01,
    // Collection: Physical
    0xA1, 0x00,

    // --- 16 digital buttons (Button page, usages 1–16) ---
    0x05, 0x09,  // Usage Page: Button
    0x19, 0x01,  // Usage Minimum: 1
    0x29, 0x10,  // Usage Maximum: 16
    0x15, 0x00,  // Logical Minimum: 0
    0x25, 0x01,  // Logical Maximum: 1
    0x75, 0x01,  // Report Size: 1
    0x95, 0x10,  // Report Count: 16
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- 4 x 16-bit axes (LSX, LSY, RSX, RSY) ---
    0x05, 0x01,  // Usage Page: Generic Desktop
    0x09, 0x30,  // Usage: X  (left stick X)
    0x09, 0x31,  // Usage: Y  (left stick Y)
    0x09, 0x33,  // Usage: Rx (right stick X)
    0x09, 0x34,  // Usage: Ry (right stick Y)
    0x16, 0x01, 0x80,  // Logical Minimum: -32767
    0x26, 0xFF, 0x7F,  // Logical Maximum:  32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x04,  // Report Count: 4
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- 2 x 8-bit triggers (Z = LT, Rz = RT) ---
    0x09, 0x32,  // Usage: Z  (left trigger)
    0x09, 0x35,  // Usage: Rz (right trigger)
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x00,  // Logical Maximum: 255
    0x75, 0x08,  // Report Size: 8
    0x95, 0x02,  // Report Count: 2
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- Hat switch (D-pad, 4-bit nibble, Null State) ---
    0x09, 0x39,  // Usage: Hat Switch
    0x15, 0x00,  // Logical Minimum: 0
    0x25, 0x07,  // Logical Maximum: 7
    0x35, 0x00,  // Physical Minimum: 0
    0x46, 0x3B, 0x01,  // Physical Maximum: 315
    0x65, 0x14,  // Unit: English Rotation / Angular Position (degrees)
    0x75, 0x04,  // Report Size: 4
    0x95, 0x01,  // Report Count: 1
    0x81, 0x42,  // Input: Data, Variable, Absolute, Null State

    // --- 4-bit pad to byte-align the hat nibble ---
    0x75, 0x04,  // Report Size: 4
    0x95, 0x01,  // Report Count: 1
    0x81, 0x03,  // Input: Constant

    // --- 13-byte output report (daemon → dext relay) ---
    // Mirrors the input layout. The dext's setReport converts output → input.
    0x09, 0x01,  // Usage: Pointer (generic output usage)
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x00,  // Logical Maximum: 255
    0x75, 0x08,  // Report Size: 8
    0x95, 0x0D,  // Report Count: 13
    0x91, 0x02,  // Output: Data, Variable, Absolute

    0xC0,  // End Collection (Physical)
    0xC0,  // End Collection (Application)
  ]

  // MARK: - Report size

  /// Total byte length of one input report.
  public static let reportSize = 13

  // MARK: - Hat switch values

  /// Raw hat-switch nibble values (stored in the low 4 bits of byte 12).
  public enum Hat: UInt8 {
    case north = 0
    case northEast = 1
    case east = 2
    case southEast = 3
    case south = 4
    case southWest = 5
    case west = 6
    case northWest = 7
    /// Null / neutral — no direction pressed. Value exceeds Logical Maximum,
    /// which the HID system interprets as the null state.
    case neutral = 8
  }

  // MARK: - Button bit indices (0-based)

  /// Button bit assignments within the 16-bit button word.
  ///
  /// Bit N corresponds to HID Button usage (N + 1).
  public enum ButtonBit: Int {
    case a = 0  // Xbox A / PS Cross
    case b = 1  // Xbox B / PS Circle
    case x = 2  // Xbox X / PS Square
    case y = 3  // Xbox Y / PS Triangle
    case leftBumper = 4  // LB / L1
    case rightBumper = 5  // RB / R1
    case leftStick = 6  // LS click / L3
    case rightStick = 7  // RS click / R3
    case start = 8  // Start / Options
    case back = 9  // Back / Share / Select
    case guide = 10  // Guide / Home
    // Bits 11–15 reserved
  }
}
