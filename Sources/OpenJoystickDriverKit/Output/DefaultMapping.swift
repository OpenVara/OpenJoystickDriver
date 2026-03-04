import CoreGraphics

/// Built-in button and axis mapping used when no saved profile exists for a device.
///
/// These values are applied by ``Profile/makeDefault(for:)`` and serve as a
/// fallback inside ``Profile/keyCode(for:)``.
public enum DefaultMapping {
  /// Maps each ``Button`` to a macOS virtual key code.
  /// Unmapped buttons produce no key event.
  public static let buttonKeyCodes: [Button: CGKeyCode] = [
    .a: 36,  // Return
    .b: 53,  // Escape
    .x: 49,  // Space
    .y: 48,  // Tab
    .start: 122,  // F1
    .back: 120,  // F2
    .leftBumper: 33,  // [
    .rightBumper: 30,  // ]
    .guide: 122,  // F1
    .dpadUp: 126, .dpadDown: 125, .dpadLeft: 123, .dpadRight: 124, .cross: 36, .circle: 53,
    .square: 49, .triangle: 48, .l1: 33, .r1: 30, .share: 120, .options: 122,
  ]

  /// Minimum stick deflection (0...1) before any output is produced.
  public static let stickDeadzone: Float = 0.15
  /// Multiplier applied to left-stick input when moving the mouse cursor.
  public static let stickMouseSensitivity: Float = 8.0
  /// Multiplier applied to right-stick input when scrolling.
  public static let stickScrollSensitivity: Float = 3.0
  /// Half-width of the cursor region in pixels for ``StickMode/mouseRegion`` mode.
  public static let stickMouseRegionRadius: Float = 200.0
  /// Default key bindings used when a stick is in ``StickMode/keyboard`` mode and
  /// the profile has no explicit mapping for a direction.  Arrow keys are used so
  /// that keyboard mode works out-of-the-box without manual configuration.
  public static let stickKeyboardDefaults: [String: UInt16] = [
    "leftStickUp": 126, "leftStickDown": 125, "leftStickLeft": 123, "leftStickRight": 124,
    "rightStickUp": 126, "rightStickDown": 125, "rightStickLeft": 123, "rightStickRight": 124,
  ]
}
