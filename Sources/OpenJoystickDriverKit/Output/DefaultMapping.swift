import CoreGraphics

public enum DefaultMapping {
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

  public static let stickDeadzone: Float = 0.15
  public static let stickMouseSensitivity: Float = 8.0
  public static let stickScrollSensitivity: Float = 3.0
}
