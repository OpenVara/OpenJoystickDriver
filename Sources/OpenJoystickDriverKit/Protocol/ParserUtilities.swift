import Foundation

/// Compares previous and current button bytes against a mapping table,
/// returning press/release events for any bits that changed.
func diffButtons(prev: UInt8, curr: UInt8, mapping: [(UInt8, Button)]) -> [ControllerEvent] {
  var events: [ControllerEvent] = []
  for (bit, button) in mapping {
    let wasPressed = (prev & bit) != 0
    let isPressed = (curr & bit) != 0
    if !wasPressed && isPressed {
      events.append(.buttonPressed(button))
    } else if wasPressed && !isPressed {
      events.append(.buttonReleased(button))
    }
  }
  return events
}
