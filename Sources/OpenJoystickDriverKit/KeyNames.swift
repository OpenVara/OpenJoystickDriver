import Foundation

/// Maps macOS virtual key codes to short human-readable names.
///
/// Used by the GUI to display key names in the mapping editor and
/// by the CLI to print readable profile output (e.g. `"A -> Return ↵ (36)"`).
public enum KeyNames {
  /// Returns the display name for a virtual key code, or `"Key N"` for unknown codes.
  public static func name(for code: UInt16) -> String { lookup[code] ?? "Key \(code)" }

  /// Full key-code-to-name table for standard US keyboard keys.
  public static let lookup: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
    12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
    22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
    32: "U", 33: "[", 34: "I", 35: "P", 36: "Return \u{21B5}", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab \u{21E5}",
    49: "Space \u{2423}", 50: "`", 51: "Delete \u{232B}", 53: "Escape \u{238B}", 96: "F5", 97: "F6",
    98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
    117: "Fwd Delete \u{2326}", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
    123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
  ]
}
