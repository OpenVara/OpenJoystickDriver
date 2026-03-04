import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("DeviceInputState Tests") struct DeviceInputStateTests {

  @Test func initialStateIsZero() {
    let state = DeviceInputState(vendorID: 100, productID: 200)
    #expect(state.pressedButtons.isEmpty)
    #expect(state.leftStickX == 0)
    #expect(state.leftStickY == 0)
    #expect(state.rightStickX == 0)
    #expect(state.rightStickY == 0)
    #expect(state.leftTrigger == 0)
    #expect(state.rightTrigger == 0)
  }

  @Test func codableRoundTrip() throws {
    var state = DeviceInputState(vendorID: 0x3537, productID: 0x1010)
    state.pressedButtons = ["a", "b"]
    state.leftStickX = 0.5
    state.leftTrigger = 0.75
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(DeviceInputState.self, from: data)
    #expect(decoded.pressedButtons == ["a", "b"])
    #expect(abs(decoded.leftStickX - 0.5) < 0.001)
    #expect(abs(decoded.leftTrigger - 0.75) < 0.001)
  }

  @Test func triggerMappingInProfile() {
    let id = DeviceIdentifier(vendorID: 100, productID: 200)
    var profile = Profile.makeDefault(for: id)
    #expect(profile.buttonMappings["leftTrigger"] == nil)
    profile.buttonMappings["leftTrigger"] = 56
    #expect(profile.buttonMappings["leftTrigger"] == 56)
    profile.buttonMappings.removeValue(forKey: "leftTrigger")
    #expect(profile.buttonMappings["leftTrigger"] == nil)
  }
}
