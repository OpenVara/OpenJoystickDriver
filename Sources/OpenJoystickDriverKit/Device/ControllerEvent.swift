/// A single change reported by a controller after parsing one input packet.
///
/// An ``InputParser`` returns an array of these for every raw packet it reads.
/// Stick values are normalized to -1.0...1.0 and trigger values to 0.0...1.0.
public enum ControllerEvent: Sendable, Equatable {
  // MARK: - Digital buttons

  /// A button was pressed down.
  case buttonPressed(Button)
  /// A button was released.
  case buttonReleased(Button)

  // MARK: - Analog axes (normalized to -1.0...1.0 for sticks, 0.0...1.0 for triggers)

  /// The left analog stick moved to a new position.
  case leftStickChanged(x: Float, y: Float)
  /// The right analog stick moved to a new position.
  case rightStickChanged(x: Float, y: Float)
  /// The left trigger changed its pressure level.
  case leftTriggerChanged(Float)
  /// The right trigger changed its pressure level.
  case rightTriggerChanged(Float)

  // MARK: - D-pad

  /// The directional pad moved to a new position (or returned to center).
  case dpadChanged(DpadDirection)
}

/// A named button on a game controller.
///
/// The first group uses Xbox-style names, the second uses PlayStation names,
/// and the last group holds generic fallbacks for controllers that do not
/// match either layout.
public enum Button: String, Sendable, CaseIterable {
  case a, b, x, y
  case leftBumper, rightBumper
  case leftStick, rightStick
  case start, back, guide
  case dpadUp, dpadDown, dpadLeft, dpadRight
  // PlayStation naming aliases
  case cross, circle, square, triangle
  case l1, r1, l2Digital, r2Digital
  case share, options, ps, touchpad
  // Generic fallbacks
  case genericButton1, genericButton2, genericButton3, genericButton4
  case genericButton5, genericButton6, genericButton7, genericButton8
}

/// One of eight compass directions, or neutral (center) for the D-pad.
public enum DpadDirection: Sendable {
  case neutral
  case north, northEast, east, southEast, south, southWest, west, northWest
}
