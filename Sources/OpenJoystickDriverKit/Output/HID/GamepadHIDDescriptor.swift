import Foundation

/// Standard HID GamePad report descriptor used by OpenJoystickDriver virtual devices.
///
/// This descriptor is intentionally generic (HID Usage Page: Generic Desktop, Usage: GamePad).
/// Do not assume consumers will apply device-specific parsing based on VID/PID.
///
/// Report layout (15 bytes total):
///   Bytes 0–1  : Button bitmask, buttons 1–16 (LSB = button 1)
///   Bytes 2–3  : Left Stick X  (Int16 LE, –32767…32767) — Usage: X  (0x30)
///   Bytes 4–5  : Left Stick Y  (Int16 LE, –32767…32767) — Usage: Y  (0x31)
///   Bytes 6–7  : Left Trigger  (Int16 LE, 0…32767)      — Usage: Z  (0x32)
///   Bytes 8–9  : Right Stick X (Int16 LE, –32767…32767) — Usage: Rx (0x33)
///   Bytes 10–11: Right Stick Y (Int16 LE, –32767…32767) — Usage: Ry (0x34)
///   Bytes 12–13: Right Trigger (Int16 LE, 0…32767)      — Usage: Rz (0x35)
///   Byte  14   : Hat switch (low nibble, 1–8 = direction, 0 = neutral) + 4-bit pad
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

    // --- 16 digital buttons (Xbox One S BT order, Button page, usages 1–16) ---
    // b0=A, b1=B, b2=X, b3=Y, b4=LB, b5=RB, b6=L3, b7=R3,
    // b8=Menu, b9=View, b10=Guide, b11=DUp, b12=DDn, b13=DLt, b14=DRt,
    // b15=Share/Capture.
    0x05, 0x09,  // Usage Page: Button
    0x19, 0x01,  // Usage Minimum: 1
    0x29, 0x10,  // Usage Maximum: 16
    0x15, 0x00,  // Logical Minimum: 0
    0x25, 0x01,  // Logical Maximum: 1
    0x75, 0x01,  // Report Size: 1
    0x95, 0x10,  // Report Count: 16
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- All 6 axes on Generic Desktop page ---
    // macOS sorts HID elements by (usage_page, usage_id), so all axes
    // must share one page to preserve index order for SDL/Chrome mapping.
    // Order: LSX(X), LSY(Y), LT(Z), RSX(Rx), RSY(Ry), RT(Rz)
    0x05, 0x01,  // Usage Page: Generic Desktop

    // Left stick: X(0x30), Y(0x31) — signed
    0x09, 0x30,  // Usage: X  (left stick X)
    0x09, 0x31,  // Usage: Y  (left stick Y)
    0x16, 0x01, 0x80,  // Logical Minimum: -32767
    0x26, 0xFF, 0x7F,  // Logical Maximum:  32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x02,  // Report Count: 2
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // Left trigger: Z(0x32) — unsigned
    0x09, 0x32,  // Usage: Z  (left trigger)
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x7F,  // Logical Maximum: 32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x01,  // Report Count: 1
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // Right stick: Rx(0x33), Ry(0x34) — signed
    0x09, 0x33,  // Usage: Rx (right stick X)
    0x09, 0x34,  // Usage: Ry (right stick Y)
    0x16, 0x01, 0x80,  // Logical Minimum: -32767
    0x26, 0xFF, 0x7F,  // Logical Maximum:  32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x02,  // Report Count: 2
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // Right trigger: Rz(0x35) — unsigned
    0x09, 0x35,  // Usage: Rz (right trigger)
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x7F,  // Logical Maximum: 32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x01,  // Report Count: 1
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- Hat switch (D-pad, 4-bit nibble, Null State, 1-based) ---
    0x05, 0x01,  // Usage Page: Generic Desktop
    0x09, 0x39,  // Usage: Hat Switch
    0x15, 0x01,  // Logical Minimum: 1
    0x25, 0x08,  // Logical Maximum: 8
    0x35, 0x00,  // Physical Minimum: 0
    0x46, 0x3B, 0x01,  // Physical Maximum: 315
    0x66, 0x14, 0x00,  // Unit: English Rotation (degrees)
    0x75, 0x04,  // Report Size: 4
    0x95, 0x01,  // Report Count: 1
    0x81, 0x42,  // Input: Data, Variable, Absolute, Null State

    // --- 4-bit pad to byte-align the hat nibble ---
    0x75, 0x04,  // Report Size: 4
    0x95, 0x01,  // Report Count: 1
    0x81, 0x03,  // Input: Constant

    // --- 15-byte output report (daemon → dext relay) ---
    // Mirrors the input layout. The dext's setReport converts output → input.
    0x09, 0x01,  // Usage: Pointer (generic output usage)
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x00,  // Logical Maximum: 255
    0x75, 0x08,  // Report Size: 8
    0x95, 0x0F,  // Report Count: 15
    0x91, 0x02,  // Output: Data, Variable, Absolute

    0xC0,  // End Collection (Physical)
    0xC0,  // End Collection (Application)
  ]

  // MARK: - Report size

  /// Total byte length of one input report.
  public static let reportSize = 15

  // MARK: - Hat switch values

  /// Raw hat-switch nibble values (stored in the low 4 bits of byte 14).
  /// 1-based directions, 0 = neutral (null state).
  public enum Hat: UInt8, Sendable {
    /// Null / neutral — no direction pressed. Value below Logical Minimum,
    /// which the HID system interprets as the null state.
    case neutral = 0
    case north = 1
    case northEast = 2
    case east = 3
    case southEast = 4
    case south = 5
    case southWest = 6
    case west = 7
    case northWest = 8
  }

  // MARK: - Button bit indices (0-based)

  /// Button bit assignments matching Xbox One S Bluetooth HID order.
  ///
  /// SDL macOS mapping for 045E:02EA:
  /// a:b0, b:b1, x:b2, y:b3, leftshoulder:b4, rightshoulder:b5,
  /// leftstick:b6, rightstick:b7, start:b8, back:b9, guide:b10,
  /// dpup:b11, dpdown:b12, dpleft:b13, dpright:b14, misc1:b15
  public enum ButtonBit: Int {
    case a = 0  // Xbox A
    case b = 1  // Xbox B
    case x = 2  // Xbox X
    case y = 3  // Xbox Y
    case leftBumper = 4  // LB
    case rightBumper = 5  // RB
    case leftStick = 6  // LS click / L3
    case rightStick = 7  // RS click / R3
    case start = 8  // Start / Menu
    case back = 9  // Back / View
    case guide = 10  // Xbox / Guide
    case dpadUp = 11
    case dpadDown = 12
    case dpadLeft = 13
    case dpadRight = 14
    case share = 15
  }

  // MARK: - D-pad button bitmask helper

  /// Returns the button bitmask bits for D-pad directions (bits 11–14).
  /// Used alongside the hat switch for dual encoding.
  public static func dpadButtonBits(for hat: Hat) -> UInt32 {
    switch hat {
    case .neutral: return 0
    case .north: return 1 << 11
    case .northEast: return (1 << 11) | (1 << 14)
    case .east: return 1 << 14
    case .southEast: return (1 << 12) | (1 << 14)
    case .south: return 1 << 12
    case .southWest: return (1 << 12) | (1 << 13)
    case .west: return 1 << 13
    case .northWest: return (1 << 11) | (1 << 13)
    }
  }
}

