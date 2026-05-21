import Foundation
import XCTest

@testable import OpenJoystickDriverKit

final class GIPAuthHandlerTests: XCTestCase {
  func test_buildAuthResponse_hostInit_correct_framing() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .hostInit)
    // Header: [Type=0x41] [Version=0x01] [State=0x21] [0x00] [Length BE: 0x00, 0x28] + 40 zero bytes
    XCTAssertTrue(response.count == 6 + 40)
    XCTAssertTrue(response[0] == GIPAuthType.host)
    XCTAssertTrue(response[1] == GIPAuthType.version)
    XCTAssertTrue(response[2] == GIPAuthState.hostInit.rawValue)
    XCTAssertTrue(response[3] == 0x00)
    // Length = 40 = 0x0028 big-endian
    XCTAssertTrue(response[4] == 0x00)
    XCTAssertTrue(response[5] == 0x28)
    // Payload is all zeros
    for i in 6..<response.count { XCTAssertTrue(response[i] == 0x00) }
  }
  func test_buildAuthResponse_hostResponse2_large_payload() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .hostResponse2)
    // 772 bytes payload + 6 byte header
    XCTAssertTrue(response.count == 6 + 772)
    XCTAssertTrue(response[2] == GIPAuthState.hostResponse2.rawValue)
    // Length = 772 = 0x0304 big-endian
    XCTAssertTrue(response[4] == 0x03)
    XCTAssertTrue(response[5] == 0x04)
  }
  func test_buildAuthResponse_all_host_states_have_correct_sizes() {
    let handler = GIPAuthHandler()
    let expected: [(GIPAuthState, Int)] = [
      (.hostInit, 40), (.hostResponse1, 176), (.hostResponse2, 772), (.hostResponse3, 132),
      (.hostResponse4, 68), (.hostResponse5, 36), (.hostComplete, 68),
    ]
    for (state, size) in expected {
      let response = handler.buildAuthResponse(state: state)
      XCTAssertTrue(response.count == 6 + size, "Wrong size for \(state)")
    }
  }
  func test_buildAuthResponse_device_state_returns_empty() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .devInit)
    XCTAssertTrue(response.isEmpty)
  }
  func test_initial_device_state_is_start() {
    let handler = GIPAuthHandler()
    XCTAssertTrue(handler.deviceState == .start)
  }
}
