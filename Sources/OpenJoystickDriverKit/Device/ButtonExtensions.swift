extension Button {
  /// A short, human-readable label for the button (e.g. `"Left Bumper (LB)"`).
  ///
  /// Used in the mapping editor and profile display.
  public var displayName: String {
    switch self {
    case .a: "A"
    case .b: "B"
    case .x: "X"
    case .y: "Y"
    case .leftBumper: "Left Bumper (LB)"
    case .rightBumper: "Right Bumper (RB)"
    case .leftStick: "Left Stick Click (LSB)"
    case .rightStick: "Right Stick Click (RSB)"
    case .start: "Start / Menu"
    case .back: "Back / View"
    case .guide: "Guide / Home"
    case .dpadUp: "D-Pad Up"
    case .dpadDown: "D-Pad Down"
    case .dpadLeft: "D-Pad Left"
    case .dpadRight: "D-Pad Right"
    case .cross: "Cross (\u{00D7})"
    case .circle: "Circle (\u{25CB})"
    case .square: "Square (\u{25A1})"
    case .triangle: "Triangle (\u{25B3})"
    case .l1: "L1"
    case .r1: "R1"
    case .l2Digital: "L2 (Digital)"
    case .r2Digital: "R2 (Digital)"
    case .share: "Share"
    case .options: "Options"
    case .ps: "PS Button"
    case .touchpad: "Touchpad Click"
    case .genericButton1: "Button 1"
    case .genericButton2: "Button 2"
    case .genericButton3: "Button 3"
    case .genericButton4: "Button 4"
    case .genericButton5: "Button 5"
    case .genericButton6: "Button 6"
    case .genericButton7: "Button 7"
    case .genericButton8: "Button 8"
    }
  }
}
