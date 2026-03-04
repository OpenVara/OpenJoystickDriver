import ApplicationServices
import CoreGraphics

/// ``OutputDispatcher`` that turns controller events into real macOS
/// keyboard and mouse events using CoreGraphics.
///
/// Reads the active ``Profile`` for each controller to decide which key
/// to press. Left stick moves the mouse cursor; right stick scrolls.
/// Requires Accessibility permission — events are silently dropped when
/// `AXIsProcessTrusted()` returns false.
public final class CGEventOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private var dpadTracker = DpadKeyTracker()
  private let profileStore: ProfileStore
  private var hasLoggedAccessibilityWarning = false
  private var leftTriggerDown = false
  private var rightTriggerDown = false
  private let triggerKeyThreshold: Float = 0.5
  /// When true, all CGEvent output is suppressed (e.g. during developer packet capture).
  public var suppressOutput = false

  /// Creates a dispatcher.
  /// - Parameter profileStore: The store used to load button and axis mappings.
  ///   Defaults to a new store that reads from `~/Library/Application Support/OpenJoystickDriver/`.
  public init(profileStore: ProfileStore = ProfileStore()) { self.profileStore = profileStore }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }
    guard AXIsProcessTrusted() else {
      if !hasLoggedAccessibilityWarning {
        hasLoggedAccessibilityWarning = true
        print("[CGEventDispatcher] Accessibility not granted" + " - skipping output")
      }
      return
    }
    hasLoggedAccessibilityWarning = false
    let profile = await profileStore.profile(for: identifier)
    for event in events { handle(event, profile: profile) }
  }

  private func handle(_ event: ControllerEvent, profile: Profile) {
    switch event {
    case .buttonPressed(let btn): handleButtonPressed(btn, profile: profile)
    case .buttonReleased(let btn): handleButtonReleased(btn, profile: profile)
    case .dpadChanged(let dir): handleDpadChanged(dir)
    case .leftStickChanged(let x, let y): handleLeftStickChanged(x: x, y: y, profile: profile)
    case .rightStickChanged(let x, let y): handleRightStickChanged(x: x, y: y, profile: profile)
    case .leftTriggerChanged(let v): handleLeftTriggerChanged(v, profile: profile)
    case .rightTriggerChanged(let v): handleRightTriggerChanged(v, profile: profile)
    }
  }

  private func handleButtonPressed(_ btn: Button, profile: Profile) {
    if let kc = profile.keyCode(for: btn) { postKey(kc, down: true) }
  }

  private func handleButtonReleased(_ btn: Button, profile: Profile) {
    if let kc = profile.keyCode(for: btn) { postKey(kc, down: false) }
  }

  private func handleDpadChanged(_ dir: DpadDirection) {
    let (release, press) = dpadTracker.transition(to: dir)
    for key in release { postKey(key, down: false) }
    for key in press { postKey(key, down: true) }
  }

  private func handleLeftStickChanged(x: Float, y: Float, profile: Profile) {
    moveMouse(
      x: x,
      y: y,
      deadzone: profile.stickDeadzone,
      sensitivity: profile.stickMouseSensitivity
    )
  }

  private func handleRightStickChanged(x: Float, y: Float, profile: Profile) {
    scrollWheel(
      x: x,
      y: y,
      deadzone: profile.stickDeadzone,
      sensitivity: profile.stickScrollSensitivity
    )
  }

  private func handleLeftTriggerChanged(_ v: Float, profile: Profile) {
    let isDown = v > triggerKeyThreshold
    if isDown != leftTriggerDown {
      leftTriggerDown = isDown
      if let kc = profile.buttonMappings["leftTrigger"] { postKey(CGKeyCode(kc), down: isDown) }
    }
  }

  private func handleRightTriggerChanged(_ v: Float, profile: Profile) {
    let isDown = v > triggerKeyThreshold
    if isDown != rightTriggerDown {
      rightTriggerDown = isDown
      if let kc = profile.buttonMappings["rightTrigger"] { postKey(CGKeyCode(kc), down: isDown) }
    }
  }

  private func postKey(_ keyCode: CGKeyCode, down: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    let ev = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)
    ev?.post(tap: .cghidEventTap)
  }

  private func moveMouse(x: Float, y: Float, deadzone: Float, sensitivity: Float) {
    let dx = abs(x) > deadzone ? Double(x * sensitivity) : 0
    let dy = abs(y) > deadzone ? Double(y * sensitivity) : 0
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
