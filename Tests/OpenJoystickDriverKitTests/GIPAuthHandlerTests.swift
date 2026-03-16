import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("GIP Auth Handler Tests") struct GIPAuthHandlerTests {

  @Test func test_buildAuthResponse_hostInit_correct_framing() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .hostInit)
    // Header: [Type=0x41] [Version=0x01] [State=0x21] [0x00] [Length BE: 0x00, 0x28] + 40 zero bytes
    #expect(response.count == 6 + 40)
    #expect(response[0] == GIPAuthType.host)
    #expect(response[1] == GIPAuthType.version)
    #expect(response[2] == GIPAuthState.hostInit.rawValue)
    #expect(response[3] == 0x00)
    // Length = 40 = 0x0028 big-endian
    #expect(response[4] == 0x00)
    #expect(response[5] == 0x28)
    // Payload is all zeros
    for i in 6..<response.count { #expect(response[i] == 0x00) }
  }

  @Test func test_buildAuthResponse_hostResponse2_large_payload() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .hostResponse2)
    // 772 bytes payload + 6 byte header
    #expect(response.count == 6 + 772)
    #expect(response[2] == GIPAuthState.hostResponse2.rawValue)
    // Length = 772 = 0x0304 big-endian
    #expect(response[4] == 0x03)
    #expect(response[5] == 0x04)
  }

  @Test func test_buildAuthResponse_all_host_states_have_correct_sizes() {
    let handler = GIPAuthHandler()
    let expected: [(GIPAuthState, Int)] = [
      (.hostInit, 40), (.hostResponse1, 176), (.hostResponse2, 772), (.hostResponse3, 132),
      (.hostResponse4, 68), (.hostResponse5, 36), (.hostComplete, 68),
    ]
    for (state, size) in expected {
      let response = handler.buildAuthResponse(state: state)
      #expect(response.count == 6 + size, "Wrong size for \(state)")
    }
  }

  @Test func test_buildAuthResponse_device_state_returns_empty() {
    let handler = GIPAuthHandler()
    let response = handler.buildAuthResponse(state: .devInit)
    #expect(response.isEmpty)
  }

  @Test func test_initial_device_state_is_start() {
    let handler = GIPAuthHandler()
    #expect(handler.deviceState == .start)
  }
}
