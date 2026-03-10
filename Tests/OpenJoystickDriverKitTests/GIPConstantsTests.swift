import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("GIP Constants Tests") struct GIPConstantsTests {

  @Test func test_deviceState_rawValues_match_windows_driver() {
    #expect(GIPDeviceState.start.rawValue == 0x00)
    #expect(GIPDeviceState.stop.rawValue == 0x01)
    #expect(GIPDeviceState.standby.rawValue == 0x02)
    #expect(GIPDeviceState.fullPower.rawValue == 0x03)
    #expect(GIPDeviceState.off.rawValue == 0x04)
    #expect(GIPDeviceState.quiesce.rawValue == 0x05)
    #expect(GIPDeviceState.enroll.rawValue == 0x06)
    #expect(GIPDeviceState.reset.rawValue == 0x07)
  }

  @Test func test_authState_expectedPayloadSize_matches_windows_driver() {
    #expect(GIPAuthState.hostInit.expectedPayloadSize == 40)
    #expect(GIPAuthState.hostResponse1.expectedPayloadSize == 176)
    #expect(GIPAuthState.hostResponse2.expectedPayloadSize == 772)
    #expect(GIPAuthState.hostResponse3.expectedPayloadSize == 132)
    #expect(GIPAuthState.hostResponse4.expectedPayloadSize == 68)
    #expect(GIPAuthState.hostResponse5.expectedPayloadSize == 36)
    #expect(GIPAuthState.hostComplete.expectedPayloadSize == 68)
  }

  @Test func test_authState_isDeviceToHost_correct_for_all_cases() {
    // Device -> Host states (rawValue < 0x20)
    let deviceStates: [GIPAuthState] = [
      .devInit, .devCertificate, .devIntermediate,
      .devData1, .devData2, .devFinal, .devComplete,
      .devStatus, .devAck1, .devAck2,
    ]
    for state in deviceStates {
      #expect(state.isDeviceToHost, "Expected \(state) to be device->host")
    }

    // Host -> Device states (rawValue >= 0x20)
    let hostStates: [GIPAuthState] = [
      .hostInit, .hostResponse1, .hostResponse2, .hostResponse3,
      .hostResponse4, .hostResponse5, .hostComplete,
    ]
    for state in hostStates {
      #expect(!state.isDeviceToHost, "Expected \(state) to be host->device")
    }
  }

  @Test func test_deviceState_has_all_8_states() {
    let allStates: [GIPDeviceState] = [
      .start, .stop, .standby, .fullPower, .off, .quiesce, .enroll, .reset,
    ]
    #expect(allStates.count == 8)
    // Verify no duplicate raw values
    let rawValues = Set(allStates.map(\.rawValue))
    #expect(rawValues.count == 8)
  }

  @Test func test_deviceState_expectedPayloadSize_nil_for_device_states() {
    let deviceStates: [GIPAuthState] = [
      .devInit, .devCertificate, .devIntermediate,
      .devData1, .devData2, .devFinal, .devComplete,
      .devStatus, .devAck1, .devAck2,
    ]
    for state in deviceStates {
      #expect(state.expectedPayloadSize == nil, "Device state \(state) should have nil payload size")
    }
  }

  @Test func test_command_constants_match_protocol() {
    #expect(GIPCommand.announce == 0x01)
    #expect(GIPCommand.status == 0x02)
    #expect(GIPCommand.keepAlive == 0x03)
    #expect(GIPCommand.power == 0x05)
    #expect(GIPCommand.authenticate == 0x06)
    #expect(GIPCommand.virtualKey == 0x07)
    #expect(GIPCommand.rumble == 0x09)
    #expect(GIPCommand.led == 0x0A)
    #expect(GIPCommand.input == 0x20)
  }

  @Test func test_authType_constants() {
    #expect(GIPAuthType.host == 0x41)
    #expect(GIPAuthType.device == 0x42)
    #expect(GIPAuthType.version == 0x01)
  }
}
