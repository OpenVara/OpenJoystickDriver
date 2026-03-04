/// All possible events emitted by parsed controller input report.
public enum ControllerEvent: Sendable, Equatable {
  // MARK: - Digital buttons
  case buttonPressed(Button)
  case buttonReleased(Button)

  // MARK: - Analog axes (normalized to -1.0...1.0 for sticks, 0.0...1.0 for triggers)
  case leftStickChanged(x: Float, y: Float)
  case rightStickChanged(x: Float, y: Float)
  case leftTriggerChanged(Float)
  case rightTriggerChanged(Float)

  // MARK: - D-pad
  case dpadChanged(DpadDirection)
}

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

public enum DpadDirection: Sendable {
  case neutral
  case north, northEast, east, southEast, south, southWest, west, northWest
}
