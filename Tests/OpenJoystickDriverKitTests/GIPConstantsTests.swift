import Foundation
import XCTest

@testable import OpenJoystickDriverKit

final class GIPConstantsTests: XCTestCase {
  func test_deviceState_rawValues_match_windows_driver() {
    XCTAssertTrue(GIPDeviceState.start.rawValue == 0x00)
    XCTAssertTrue(GIPDeviceState.stop.rawValue == 0x01)
    XCTAssertTrue(GIPDeviceState.standby.rawValue == 0x02)
    XCTAssertTrue(GIPDeviceState.fullPower.rawValue == 0x03)
    XCTAssertTrue(GIPDeviceState.off.rawValue == 0x04)
    XCTAssertTrue(GIPDeviceState.quiesce.rawValue == 0x05)
    XCTAssertTrue(GIPDeviceState.enroll.rawValue == 0x06)
    XCTAssertTrue(GIPDeviceState.reset.rawValue == 0x07)
  }
  func test_authState_expectedPayloadSize_matches_windows_driver() {
    XCTAssertTrue(GIPAuthState.hostInit.expectedPayloadSize == 40)
    XCTAssertTrue(GIPAuthState.hostResponse1.expectedPayloadSize == 176)
    XCTAssertTrue(GIPAuthState.hostResponse2.expectedPayloadSize == 772)
    XCTAssertTrue(GIPAuthState.hostResponse3.expectedPayloadSize == 132)
    XCTAssertTrue(GIPAuthState.hostResponse4.expectedPayloadSize == 68)
    XCTAssertTrue(GIPAuthState.hostResponse5.expectedPayloadSize == 36)
    XCTAssertTrue(GIPAuthState.hostComplete.expectedPayloadSize == 68)
  }
  func test_authState_isDeviceToHost_correct_for_all_cases() {
    // Device -> Host states (rawValue < 0x20)
    let deviceStates: [GIPAuthState] = [
      .devInit, .devCertificate, .devIntermediate, .devData1, .devData2, .devFinal, .devComplete,
      .devStatus, .devAck1, .devAck2,
    ]
    for state in deviceStates {
      XCTAssertTrue(state.isDeviceToHost, "Expected \(state) to be device->host")
    }

    // Host -> Device states (rawValue >= 0x20)
    let hostStates: [GIPAuthState] = [
      .hostInit, .hostResponse1, .hostResponse2, .hostResponse3, .hostResponse4, .hostResponse5,
      .hostComplete,
    ]
    for state in hostStates {
      XCTAssertTrue(!state.isDeviceToHost, "Expected \(state) to be host->device")
    }
  }
  func test_deviceState_has_all_8_states() {
    let allStates: [GIPDeviceState] = [
      .start, .stop, .standby, .fullPower, .off, .quiesce, .enroll, .reset,
    ]
    XCTAssertTrue(allStates.count == 8)
    // Verify no duplicate raw values
    let rawValues = Set(allStates.map(\.rawValue))
    XCTAssertTrue(rawValues.count == 8)
  }
  func test_deviceState_expectedPayloadSize_nil_for_device_states() {
    let deviceStates: [GIPAuthState] = [
      .devInit, .devCertificate, .devIntermediate, .devData1, .devData2, .devFinal, .devComplete,
      .devStatus, .devAck1, .devAck2,
    ]
    for state in deviceStates {
      XCTAssertTrue(
        state.expectedPayloadSize == nil,
        "Device state \(state) should have nil payload size"
      )
    }
  }
  func test_command_constants_match_protocol() {
    XCTAssertTrue(GIPCommand.announce == 0x01)
    XCTAssertTrue(GIPCommand.status == 0x02)
    XCTAssertTrue(GIPCommand.keepAlive == 0x03)
    XCTAssertTrue(GIPCommand.power == 0x05)
    XCTAssertTrue(GIPCommand.authenticate == 0x06)
    XCTAssertTrue(GIPCommand.virtualKey == 0x07)
    XCTAssertTrue(GIPCommand.rumble == 0x09)
    XCTAssertTrue(GIPCommand.led == 0x0A)
    XCTAssertTrue(GIPCommand.input == 0x20)
  }
  func test_authType_constants() {
    XCTAssertTrue(GIPAuthType.host == 0x41)
    XCTAssertTrue(GIPAuthType.device == 0x42)
    XCTAssertTrue(GIPAuthType.version == 0x01)
  }
}
