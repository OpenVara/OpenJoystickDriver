import AppKit
import ApplicationServices
import CoreGraphics

/// ``OutputDispatcher`` that turns controller events into real macOS
/// keyboard and mouse events using CoreGraphics.
///
/// Reads the active ``Profile`` for each controller to decide which key
/// to press. Left stick moves the mouse cursor; right stick scrolls.
/// Requires Accessibility permission - events are silently dropped when
/// `AXIsProcessTrusted()` returns false.
public final class CGEventOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private struct StickKeyTracker {
    var upDown = false
    var downDown = false
    var leftDown = false
    var rightDown = false
  }

  /// Per-device profile cache entry. Re-fetched from the actor at most once per second.
  private struct ProfileCacheEntry {
    var profile: Profile
    var fetchedAt: Date
  }

  private var dpadTracker = DpadKeyTracker()
  private let profileStore: ProfileStore
  private var hasLoggedAccessibilityWarning = false
  private var leftTriggerDown = false
  private var rightTriggerDown = false
  private let triggerKeyThreshold: Float = 0.5
  private var leftStickTracker = StickKeyTracker()
  private var rightStickTracker = StickKeyTracker()
  private var leftStickCenter: CGPoint?
  private var rightStickCenter: CGPoint?
  /// Local profile cache keyed by "{vendorID}:{productID}". Avoids one actor hop per USB packet.
  private var profileCache: [String: ProfileCacheEntry] = [:]
  private let profileCacheTTL: TimeInterval = 1.0

  /// When true, all CGEvent output is suppressed (e.g. during developer packet capture).
  /// Setting this also invalidates the profile cache so the next dispatch re-fetches cleanly.
  public var suppressOutput = false {
    didSet { if suppressOutput != oldValue { profileCache.removeAll() } }
  }

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
    let profile = await cachedProfile(for: identifier)
    for event in events { handle(event, profile: profile) }
  }

  /// Returns a cached profile for the device, re-fetching from the actor at most once per second.
  private func cachedProfile(for identifier: DeviceIdentifier) async -> Profile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    let now = Date()
    if let entry = profileCache[key], now.timeIntervalSince(entry.fetchedAt) < profileCacheTTL {
      return entry.profile
    }
    let fresh = await profileStore.profile(for: identifier)
    profileCache[key] = ProfileCacheEntry(profile: fresh, fetchedAt: now)
    return fresh
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
    switch profile.leftStickMode {
    case .mouse:
      let dx = abs(x) > profile.stickDeadzone ? Double(x * profile.stickMouseSensitivity) : 0
      let dy = abs(y) > profile.stickDeadzone ? Double(y * profile.stickMouseSensitivity) : 0
      if dx != 0 || dy != 0 { postMouseDelta(dx: dx, dy: dy) }
    case .mouseRegion:
      moveMouseRegion(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        radius: profile.stickMouseRegionRadius,
        center: &leftStickCenter
      )
    case .scroll:
      scrollWheel(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        sensitivity: profile.stickScrollSensitivity
      )
    case .keyboard:
      let lDefaults = DefaultMapping.stickKeyboardDefaults
      handleStickKeyboard(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        tracker: &leftStickTracker,
        upKey: profile.buttonMappings["leftStickUp"] ?? lDefaults["leftStickUp"],
        downKey: profile.buttonMappings["leftStickDown"] ?? lDefaults["leftStickDown"],
        leftKey: profile.buttonMappings["leftStickLeft"] ?? lDefaults["leftStickLeft"],
        rightKey: profile.buttonMappings["leftStickRight"] ?? lDefaults["leftStickRight"]
      )
    }
  }

  private func handleRightStickChanged(x: Float, y: Float, profile: Profile) {
    switch profile.rightStickMode {
    case .mouse:
      let dx = abs(x) > profile.stickDeadzone ? Double(x * profile.stickMouseSensitivity) : 0
      let dy = abs(y) > profile.stickDeadzone ? Double(y * profile.stickMouseSensitivity) : 0
      if dx != 0 || dy != 0 { postMouseDelta(dx: dx, dy: dy) }
    case .mouseRegion:
      moveMouseRegion(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        radius: profile.stickMouseRegionRadius,
        center: &rightStickCenter
      )
    case .scroll:
      scrollWheel(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        sensitivity: profile.stickScrollSensitivity
      )
    case .keyboard:
      let rDefaults = DefaultMapping.stickKeyboardDefaults
      handleStickKeyboard(
        x: x,
        y: y,
        deadzone: profile.stickDeadzone,
        tracker: &rightStickTracker,
        upKey: profile.buttonMappings["rightStickUp"] ?? rDefaults["rightStickUp"],
        downKey: profile.buttonMappings["rightStickDown"] ?? rDefaults["rightStickDown"],
        leftKey: profile.buttonMappings["rightStickLeft"] ?? rDefaults["rightStickLeft"],
        rightKey: profile.buttonMappings["rightStickRight"] ?? rDefaults["rightStickRight"]
      )
    }
  }

  private func handleStickKeyboard(
    x: Float,
    y: Float,
    deadzone: Float,
    tracker: inout StickKeyTracker,
    upKey: UInt16?,
    downKey: UInt16?,
    leftKey: UInt16?,
    rightKey: UInt16?
  ) {
    // ly convention: negative = physical up (GIPParser negates raw LSY).
    // Negate again here so wantUp fires when stick is pushed up.
    let ky = -y
    // Hysteresis: a direction is pressed when the stick exceeds `deadzone`
    // and is only released when it falls back below `releaseZone` (half the deadzone).
    // This prevents analog stick jitter around the threshold from producing rapid
    // key-down / key-up bursts that applications see as "1 input at a time".
    let releaseZone = deadzone * 0.5
    let wantUp = tracker.upDown ? ky > releaseZone : ky > deadzone
    let wantDown = tracker.downDown ? ky < -releaseZone : ky < -deadzone
    let wantRight = tracker.rightDown ? x > releaseZone : x > deadzone
    let wantLeft = tracker.leftDown ? x < -releaseZone : x < -deadzone

    if tracker.upDown != wantUp {
      tracker.upDown = wantUp
      if let k = upKey { postKey(CGKeyCode(k), down: wantUp) }
    }
    if tracker.downDown != wantDown {
      tracker.downDown = wantDown
      if let k = downKey { postKey(CGKeyCode(k), down: wantDown) }
    }
    if tracker.rightDown != wantRight {
      tracker.rightDown = wantRight
      if let k = rightKey { postKey(CGKeyCode(k), down: wantRight) }
    }
    if tracker.leftDown != wantLeft {
      tracker.leftDown = wantLeft
      if let k = leftKey { postKey(CGKeyCode(k), down: wantLeft) }
    }
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

  // MARK: - Event posting

  private func postKey(_ keyCode: CGKeyCode, down: Bool) {
    // nil source matches OpenTabletDriver's CGEventCreateKeyboardEvent(NULL, ...) pattern -
    // the OS supplies its own default source state, which routes cleanly to the key window
    // without any synthetic-event filtering that some apps apply to non-null sources.
    let ev = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
    ev?.post(tap: .cghidEventTap)
  }

  /// Returns the current cursor position in CoreGraphics coordinates (origin top-left).
  ///
  /// `NSEvent.mouseLocation` uses Cocoa coordinates (origin bottom-left); we flip Y
  /// using the main display height to get the CG coordinate system used by CGEvent.
  private func currentCursorPosition() -> CGPoint {
    let cocoaPos = NSEvent.mouseLocation
    let screenH = CGDisplayBounds(CGMainDisplayID()).height
    return CGPoint(x: cocoaPos.x, y: screenH - cocoaPos.y)
  }

  /// Posts a relative mouse movement.
  ///
  /// Reads the cursor position via `NSEvent.mouseLocation` (which reflects our own
  /// previously-posted events via `.cghidEventTap`) and applies the delta as an
  /// absolute position move.  This avoids the left-edge cursor-snap bug that occurs
  /// when reading from `.hidSystemState` after synthesised events.
  private func postMouseDelta(dx: Double, dy: Double) {
    let src = CGEventSource(stateID: .hidSystemState)
    let cur = currentCursorPosition()
    let ev = CGEvent(
      mouseEventSource: src,
      mouseType: .mouseMoved,
      mouseCursorPosition: CGPoint(x: cur.x + dx, y: cur.y + dy),
      mouseButton: .left
    )
    ev?.setDoubleValueField(.mouseEventDeltaX, value: dx)
    ev?.setDoubleValueField(.mouseEventDeltaY, value: dy)
    ev?.post(tap: .cghidEventTap)
  }

  private func moveMouseRegion(
    x: Float,
    y: Float,
    deadzone: Float,
    radius: Float,
    center: inout CGPoint?
  ) {
    let ax = abs(x) > deadzone ? x : 0
    let ay = abs(y) > deadzone ? y : 0
    guard ax != 0 || ay != 0 else {
      if let c = center {
        let src = CGEventSource(stateID: .combinedSessionState)
        let ev = CGEvent(
          mouseEventSource: src,
          mouseType: .mouseMoved,
          mouseCursorPosition: c,
          mouseButton: .left
        )
        ev?.post(tap: .cghidEventTap)
        center = nil
      }
      return
    }
    if center == nil { center = currentCursorPosition() }
    guard let c = center else { return }
    let newPos = CGPoint(x: c.x + Double(ax) * Double(radius), y: c.y + Double(ay) * Double(radius))
    let src = CGEventSource(stateID: .combinedSessionState)
    let ev = CGEvent(
      mouseEventSource: src,
      mouseType: .mouseMoved,
      mouseCursorPosition: newPos,
      mouseButton: .left
    )
    ev?.setDoubleValueField(.mouseEventDeltaX, value: Double(ax) * Double(radius))
    ev?.setDoubleValueField(.mouseEventDeltaY, value: Double(ay) * Double(radius))
    ev?.post(tap: .cghidEventTap)
  }

  private func scrollWheel(x: Float, y: Float, deadzone: Float, sensitivity: Float) {
    guard abs(x) > deadzone || abs(y) > deadzone else { return }
    let src = CGEventSource(stateID: .hidSystemState)
    let ev = CGEvent(
      scrollWheelEvent2Source: src,
      units: .line,
      wheelCount: 2,
      wheel1: Int32(-y * sensitivity),
      wheel2: Int32(x * sensitivity),
      wheel3: 0
    )
    ev?.post(tap: .cgSessionEventTap)
  }
}
