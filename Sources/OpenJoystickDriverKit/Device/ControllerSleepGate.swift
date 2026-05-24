import Foundation

private let controllerSleepStickDeadzone: Float = 0.15
private let controllerSleepTriggerDeadzone: Float = 0.05

enum ControllerSleepDisposition: Equatable {
  case forward
  case consumeWhileSleeping
  case consumeWake
}

struct ControllerSleepGate {
  private(set) var isSleeping = false
  private var lastActiveNanoseconds: UInt64?
  private let idleTimeoutNanoseconds: UInt64

  init(idleTimeoutNanoseconds: UInt64 = 30_000_000_000) {
    self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
  }

  mutating func handleInput(
    events: [ControllerEvent],
    previousState: DeviceInputState,
    nextState: DeviceInputState,
    now: UInt64
  ) -> ControllerSleepDisposition {
    if isSleeping {
      if Self.containsWakeEvent(events) {
        isSleeping = false
        lastActiveNanoseconds = now
        return .consumeWake
      }
      return .consumeWhileSleeping
    }

    if !previousState.isEffectivelyNeutral || !nextState.isEffectivelyNeutral {
      lastActiveNanoseconds = now
    } else if lastActiveNanoseconds == nil {
      lastActiveNanoseconds = now
    }

    return .forward
  }

  mutating func idleTransition(currentState: DeviceInputState, now: UInt64) -> [ControllerEvent]? {
    guard !isSleeping else { return nil }

    if !currentState.isEffectivelyNeutral {
      lastActiveNanoseconds = now
      return nil
    }

    guard let lastActiveNanoseconds else {
      self.lastActiveNanoseconds = now
      return nil
    }

    guard now &- lastActiveNanoseconds >= idleTimeoutNanoseconds else { return nil }

    isSleeping = true
    return currentState.neutralizingEvents()
  }

  private static func containsWakeEvent(_ events: [ControllerEvent]) -> Bool {
    for event in events {
      switch event {
      case .buttonPressed:
        return true
      case .dpadChanged(let direction):
        switch direction {
        case .neutral:
          break
        default:
          return true
        }
      default:
        break
      }
    }
    return false
  }
}

extension DeviceInputState {
  var isEffectivelyNeutral: Bool {
    if pressedButtons.contains(where: { !$0.isEmpty }) { return false }
    if abs(leftStickX) > controllerSleepStickDeadzone { return false }
    if abs(leftStickY) > controllerSleepStickDeadzone { return false }
    if abs(rightStickX) > controllerSleepStickDeadzone { return false }
    if abs(rightStickY) > controllerSleepStickDeadzone { return false }
    if leftTrigger > controllerSleepTriggerDeadzone { return false }
    if rightTrigger > controllerSleepTriggerDeadzone { return false }
    return true
  }

  func applying(events: [ControllerEvent]) -> DeviceInputState {
    var next = self
    next.apply(events: events)
    return next
  }

  mutating func apply(events: [ControllerEvent]) {
    for event in events {
      switch event {
      case .buttonPressed(let button):
        let raw = button.rawValue
        if !pressedButtons.contains(raw) {
          pressedButtons.append(raw)
        }
      case .buttonReleased(let button):
        pressedButtons.removeAll { $0 == button.rawValue }
      case .leftStickChanged(let x, let y):
        leftStickX = x
        leftStickY = y
      case .rightStickChanged(let x, let y):
        rightStickX = x
        rightStickY = y
      case .leftTriggerChanged(let v):
        leftTrigger = v
      case .rightTriggerChanged(let v):
        rightTrigger = v
      case .dpadChanged(let direction):
        applyDpad(direction)
      }
    }
  }

  func neutralizingEvents() -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    var needsDpadNeutral = false

    for raw in pressedButtons {
      guard let button = Button(rawValue: raw) else { continue }
      switch button {
      case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
        needsDpadNeutral = true
      default:
        events.append(.buttonReleased(button))
      }
    }

    if needsDpadNeutral {
      events.append(.dpadChanged(.neutral))
    }
    if abs(leftStickX) > controllerSleepStickDeadzone
      || abs(leftStickY) > controllerSleepStickDeadzone
    {
      events.append(.leftStickChanged(x: 0, y: 0))
    }
    if abs(rightStickX) > controllerSleepStickDeadzone
      || abs(rightStickY) > controllerSleepStickDeadzone
    {
      events.append(.rightStickChanged(x: 0, y: 0))
    }
    if leftTrigger > controllerSleepTriggerDeadzone {
      events.append(.leftTriggerChanged(0))
    }
    if rightTrigger > controllerSleepTriggerDeadzone {
      events.append(.rightTriggerChanged(0))
    }

    return events
  }

  func currentEvents() -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let dpadButtons = Set(pressedButtons)

    for raw in pressedButtons.sorted() {
      guard let button = Button(rawValue: raw) else { continue }
      switch button {
      case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
        break
      default:
        events.append(.buttonPressed(button))
      }
    }

    if dpadButtons.contains(Button.dpadUp.rawValue)
      || dpadButtons.contains(Button.dpadDown.rawValue)
      || dpadButtons.contains(Button.dpadLeft.rawValue)
      || dpadButtons.contains(Button.dpadRight.rawValue)
    {
      events.append(.dpadChanged(currentDpadDirection()))
    }
    if abs(leftStickX) > controllerSleepStickDeadzone
      || abs(leftStickY) > controllerSleepStickDeadzone
    {
      events.append(.leftStickChanged(x: leftStickX, y: leftStickY))
    }
    if abs(rightStickX) > controllerSleepStickDeadzone
      || abs(rightStickY) > controllerSleepStickDeadzone
    {
      events.append(.rightStickChanged(x: rightStickX, y: rightStickY))
    }
    if leftTrigger > controllerSleepTriggerDeadzone {
      events.append(.leftTriggerChanged(leftTrigger))
    }
    if rightTrigger > controllerSleepTriggerDeadzone {
      events.append(.rightTriggerChanged(rightTrigger))
    }

    return events
  }

  private mutating func applyDpad(_ direction: DpadDirection) {
    let dpadButtons = Set([
      Button.dpadUp.rawValue,
      Button.dpadDown.rawValue,
      Button.dpadLeft.rawValue,
      Button.dpadRight.rawValue,
    ])
    pressedButtons.removeAll { dpadButtons.contains($0) }

    func append(_ button: Button) {
      let raw = button.rawValue
      if !pressedButtons.contains(raw) {
        pressedButtons.append(raw)
      }
    }

    switch direction {
    case .neutral:
      break
    case .north:
      append(.dpadUp)
    case .northEast:
      append(.dpadUp)
      append(.dpadRight)
    case .east:
      append(.dpadRight)
    case .southEast:
      append(.dpadDown)
      append(.dpadRight)
    case .south:
      append(.dpadDown)
    case .southWest:
      append(.dpadDown)
      append(.dpadLeft)
    case .west:
      append(.dpadLeft)
    case .northWest:
      append(.dpadUp)
      append(.dpadLeft)
    }
  }

  private func currentDpadDirection() -> DpadDirection {
    let up = pressedButtons.contains(Button.dpadUp.rawValue)
    let down = pressedButtons.contains(Button.dpadDown.rawValue)
    let left = pressedButtons.contains(Button.dpadLeft.rawValue)
    let right = pressedButtons.contains(Button.dpadRight.rawValue)

    switch (up, down, left, right) {
    case (true, false, false, false):
      return .north
    case (true, false, false, true):
      return .northEast
    case (false, false, false, true):
      return .east
    case (false, true, false, true):
      return .southEast
    case (false, true, false, false):
      return .south
    case (false, true, true, false):
      return .southWest
    case (false, false, true, false):
      return .west
    case (true, false, true, false):
      return .northWest
    default:
      return .neutral
    }
  }
}
