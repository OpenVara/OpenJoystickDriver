import Testing

@testable import OpenJoystickDriverKit

struct ControllerSleepGateTests {
  @Test
  func testControllerSleepsAfterNeutralIdleTimeout() {
    var gate = ControllerSleepGate(idleTimeoutNanoseconds: 5)
    let neutral = DeviceInputState(vendorID: 100, productID: 200)
    var pressed = neutral
    pressed.pressedButtons = [Button.a.rawValue]

    #expect(gate.handleInput(
        events: [.buttonPressed(.a)],
        previousState: neutral,
        nextState: pressed,
        now: 10
      ) == .forward)
    #expect(gate.handleInput(
        events: [.buttonReleased(.a)],
        previousState: pressed,
        nextState: neutral,
        now: 12
      ) == .forward)

    #expect(gate.idleTransition(currentState: neutral, now: 16) == nil)

    let sleepReset = gate.idleTransition(currentState: neutral, now: 17)
    #expect(sleepReset != nil)
    #expect(sleepReset?.isEmpty == true)
    #expect(gate.isSleeping)
  }

  @Test

  func testSleepingControllerConsumesAnalogInputUntilWakeButton() {
    var gate = ControllerSleepGate(idleTimeoutNanoseconds: 5)
    let neutral = DeviceInputState(vendorID: 100, productID: 200)
    var pressed = neutral
    pressed.pressedButtons = [Button.a.rawValue]

    _ = gate.handleInput(
      events: [.buttonPressed(.a)],
      previousState: neutral,
      nextState: pressed,
      now: 10
    )
    _ = gate.handleInput(
      events: [.buttonReleased(.a)],
      previousState: pressed,
      nextState: neutral,
      now: 12
    )
    _ = gate.idleTransition(currentState: neutral, now: 17)

    var stickMoved = neutral
    stickMoved.leftStickX = 0.8

    #expect(gate.handleInput(
        events: [.leftStickChanged(x: 0.8, y: 0)],
        previousState: neutral,
        nextState: stickMoved,
        now: 18
      ) == .consumeWhileSleeping)
    #expect(gate.isSleeping)

    #expect(gate.handleInput(
        events: [.buttonPressed(.guide)],
        previousState: neutral,
        nextState: pressed,
        now: 19
      ) == .consumeWake)
    #expect(!(gate.isSleeping))
  }

  @Test

  func testNeutralizingEventsReleaseHeldControls() {
    var state = DeviceInputState(vendorID: 100, productID: 200)
    state.pressedButtons = [Button.a.rawValue, Button.dpadUp.rawValue]
    state.leftStickX = 0.5
    state.rightStickY = -0.5
    state.leftTrigger = 0.4

    let events = state.neutralizingEvents()

    #expect(events.contains(.buttonReleased(.a)))
    #expect(events.contains(.dpadChanged(.neutral)))
    #expect(events.contains(.leftStickChanged(x: 0, y: 0)))
    #expect(events.contains(.rightStickChanged(x: 0, y: 0)))
    #expect(events.contains(.leftTriggerChanged(0)))
  }
}
