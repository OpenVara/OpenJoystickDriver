import Foundation
import XCTest

@testable import OpenJoystickDriverKit

final class DeviceInputStateTests: XCTestCase {
  func testInitialStateIsZero() {
    let state = DeviceInputState(vendorID: 100, productID: 200)
    XCTAssertTrue(state.pressedButtons.isEmpty)
    XCTAssertTrue(state.leftStickX == 0)
    XCTAssertTrue(state.leftStickY == 0)
    XCTAssertTrue(state.rightStickX == 0)
    XCTAssertTrue(state.rightStickY == 0)
    XCTAssertTrue(state.leftTrigger == 0)
    XCTAssertTrue(state.rightTrigger == 0)
  }
  func testCodableRoundTrip() throws {
    var state = DeviceInputState(vendorID: 0x3537, productID: 0x1010)
    state.pressedButtons = ["a", "b"]
    state.leftStickX = 0.5
    state.leftTrigger = 0.75
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(DeviceInputState.self, from: data)
    XCTAssertTrue(decoded.pressedButtons == ["a", "b"])
    XCTAssertTrue(abs(decoded.leftStickX - 0.5) < 0.001)
    XCTAssertTrue(abs(decoded.leftTrigger - 0.75) < 0.001)
  }

}
