import ApplicationServices
import CoreGraphics

public final class CGEventOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private var dpadTracker = DpadKeyTracker()
  private let profileStore: ProfileStore

  public init(profileStore: ProfileStore = ProfileStore()) { self.profileStore = profileStore }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard AXIsProcessTrusted() else {
      print("[CGEventDispatcher] Accessibility not granted" + " - skipping output")
      return
    }
    let profile = await profileStore.profile(for: identifier)
    for event in events { handle(event, profile: profile) }
  }

  private func handle(_ event: ControllerEvent, profile: Profile) {
    switch event {
    case .buttonPressed(let btn): if let kc = profile.keyCode(for: btn) { postKey(kc, down: true) }
    case .buttonReleased(let btn):
      if let kc = profile.keyCode(for: btn) { postKey(kc, down: false) }
    case .dpadChanged(let dir):
      let (release, press) = dpadTracker.transition(to: dir)
      for key in release { postKey(key, down: false) }
      for key in press { postKey(key, down: true) }
    case .leftStickChanged(let x, let y):
      moveMouse(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        sensitivity: profile.stickMouseSensitivity
      )
    case .rightStickChanged(let x, let y):
      scrollWheel(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        sensitivity: profile.stickScrollSensitivity
      )
    case .leftTriggerChanged, .rightTriggerChanged: break
    }
  }

  private func postKey(_ keyCode: CGKeyCode, down: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    let ev = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)
    ev?.post(tap: .cghidEventTap)
  }

  private func moveMouse(x: Float, y: Float, deadzone: Float, sensitivity: Float) {
    let dx = abs(x) > deadzone ? Double(x * sensitivity) : 0
    let dy = abs(y) > deadzone ? Double(-y * sensitivity) : 0
    guard dx != 0 || dy != 0 else { return }
    let src = CGEventSource(stateID: .hidSystemState)
    let ev = CGEvent(source: src)
    ev?.type = .mouseMoved
    ev?.setDoubleValueField(.mouseEventDeltaX, value: dx)
    ev?.setDoubleValueField(.mouseEventDeltaY, value: dy)
    ev?.post(tap: .cghidEventTap)
  }

  private func scrollWheel(x: Float, y: Float, deadzone: Float, sensitivity: Float) {
    guard abs(x) > deadzone || abs(y) > deadzone else { return }
    let scrollY = Int32(-y * sensitivity)
    let scrollX = Int32(x * sensitivity)
    let src = CGEventSource(stateID: .hidSystemState)
    let ev = CGEvent(
      scrollWheelEvent2Source: src,
      units: .line,
      wheelCount: 2,
      wheel1: scrollY,
      wheel2: scrollX,
      wheel3: 0
    )
    ev?.post(tap: .cgSessionEventTap)
  }
}
