import CGamepadDescriptor
import Foundation

/// Xbox One S-compatible HID gamepad report descriptor.
///
/// Matches the real Xbox One S Bluetooth HID layout so that Chrome, Safari,
/// SDL, and GCController apply correct device-specific mapping for VID/PID
/// 0x045E:0x02EA. Button and axis ordering follows the SDL macOS mapping
/// string for this VID/PID.
///
/// Report layout (15 bytes total):
///   Bytes 0–1  : Button bitmask, buttons 1–15 + 1-bit pad (LSB = button 1)
///   Bytes 2–3  : Left Stick X  (Int16 LE, –32767…32767) — Usage: X  (0x30)
///   Bytes 4–5  : Left Stick Y  (Int16 LE, –32767…32767) — Usage: Y  (0x31)
///   Bytes 6–7  : Left Trigger  (Int16 LE, 0…32767)      — Usage: Z  (0x32)
///   Bytes 8–9  : Right Stick X (Int16 LE, –32767…32767) — Usage: Rx (0x33)
///   Bytes 10–11: Right Stick Y (Int16 LE, –32767…32767) — Usage: Ry (0x34)
///   Bytes 12–13: Right Trigger (Int16 LE, 0…32767)      — Usage: Rz (0x35)
///   Byte  14   : Hat switch (low nibble, 1–8 = direction, 0 = neutral) + 4-bit pad
public enum GamepadHIDDescriptor {
  // MARK: - Report descriptor bytes

  /// Raw HID report descriptor that describes the virtual gamepad layout.
  public static let descriptor: [UInt8] = withUnsafeBytes(of: GAMEPAD_HID_REPORT_DESCRIPTOR) {
    Array($0.bindMemory(to: UInt8.self))
  }

  // MARK: - Report size

  /// Total byte length of one input report.
  public static let reportSize = 15

  // MARK: - Hat switch values

  /// Raw hat-switch nibble values (stored in the low 4 bits of byte 14).
  /// 1-based directions, 0 = neutral (null state).
  public enum Hat: UInt8 {
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
  /// dpup:b11, dpdown:b12, dpleft:b13, dpright:b14
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
    case dpadRight = 14  // Bit 15: padding (15 buttons + 1 pad bit)
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
