import CoreGraphics

/// Tracks currently-pressed D-pad keys and computes
/// key-down / key-up transitions when direction changes.
struct DpadKeyTracker {
  private var currentKeys: Set<CGKeyCode> = []

  /// Returns (keysToRelease, keysToPress) for direction change.
  mutating func transition(to direction: DpadDirection) -> (
    release: Set<CGKeyCode>, press: Set<CGKeyCode>
  ) {
    let newKeys = keys(for: direction)
    let toRelease = currentKeys.subtracting(newKeys)
    let toPress = newKeys.subtracting(currentKeys)
    currentKeys = newKeys
    return (toRelease, toPress)
  }

  private func keys(for direction: DpadDirection) -> Set<CGKeyCode> {
    switch direction {
    case .neutral: []
    case .north: [126]
    case .south: [125]
    case .east: [124]
    case .west: [123]
    case .northEast: [126, 124]
    case .northWest: [126, 123]
    case .southEast: [125, 124]
    case .southWest: [125, 123]
    }
  }
}
