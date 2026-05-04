import Foundation
import SwiftUSB

/// Handles the GIP authentication sub-protocol (CMD 0x06).
///
/// Responds to device auth messages with correctly-framed dummy payloads.
/// The Windows driver analysis shows lenient enforcement — structurally valid
/// but cryptographically empty responses allow the device to eventually
/// transition to FULL_POWER via xboxgip.sys retry/timeout logic.
final class GIPAuthHandler: @unchecked Sendable {

  private let outEndpoint: UInt8

  /// Current device power state, driven by auth progress.
  private(set) var deviceState: GIPDeviceState = .start

  init(outEndpoint: UInt8 = 0x02) {
    self.outEndpoint = outEndpoint
  }

  /// Maps device auth states to the host response state we should send.
  private static let responseMap: [GIPAuthState: GIPAuthState] = [
    .devInit: .hostInit, .devCertificate: .hostResponse1, .devIntermediate: .hostResponse2,
    .devData1: .hostResponse3, .devData2: .hostResponse4, .devFinal: .hostResponse5,
    .devComplete: .hostComplete,
  ]

  /// Handle an incoming CMD 0x06 auth message from the device.
  ///
  /// Parses the auth sub-header, determines the appropriate response,
  /// and sends it. Updates `deviceState` on key transitions.
  func handleAuthMessage(payload: Data, handle: USBDeviceHandle, sequencer: inout GIPSequencer)
    throws
  {
    guard payload.count >= 6 else {
      print("[GIPAuth] Auth payload too short: \(payload.count) bytes")
      return
    }

    let type = payload[0]
    let state = payload[2]

    guard type == GIPAuthType.device else {
      print("[GIPAuth] Unexpected auth type: 0x\(String(type, radix: 16))")
      return
    }

    guard let deviceAuthState = GIPAuthState(rawValue: state) else {
      print("[GIPAuth] Unknown auth state: 0x\(String(state, radix: 16))")
      return
    }

    print("[GIPAuth] Received \(deviceAuthState)")

    // Transition to ENROLL on first auth message
    if deviceState == .start {
      deviceState = .enroll
      print("[GIPAuth] State -> \(deviceState)")
    }

    // Transition to FULL_POWER on completion/status
    if deviceAuthState == .devComplete || deviceAuthState == .devStatus {
      if deviceState == .enroll {
        deviceState = .fullPower
        print("[GIPAuth] State -> \(deviceState)")
      }
    }

    // Send response if one is expected for this device state
    guard let responseState = Self.responseMap[deviceAuthState] else {
      print("[GIPAuth] No response needed for \(deviceAuthState)")
      return
    }

    let responsePayload = buildAuthResponse(state: responseState)
    try sendAuthPacket(payload: responsePayload, handle: handle, sequencer: &sequencer)
    print("[GIPAuth] Sent \(responseState)")
  }

  /// Build a complete auth sub-protocol payload for a host->device response.
  ///
  /// Format: [Type=0x41] [Version=0x01] [State] [0x00] [Length BE: 2B] [Payload zeros...]
  func buildAuthResponse(state: GIPAuthState) -> [UInt8] {
    guard let size = state.expectedPayloadSize else { return [] }
    var response: [UInt8] = [
      GIPAuthType.host, GIPAuthType.version, state.rawValue, 0x00, UInt8((size >> 8) & 0xFF),
      UInt8(size & 0xFF),
    ]
    response += [UInt8](repeating: 0, count: size)
    return response
  }

  /// Wrap an auth sub-protocol payload in a GIP CMD 0x06 packet and send it.
  private func sendAuthPacket(
    payload: [UInt8],
    handle: USBDeviceHandle,
    sequencer: inout GIPSequencer
  ) throws {
    let seq = sequencer.next(for: GIPCommand.authenticate)
    var packet: [UInt8] = [GIPCommand.authenticate, GIPOption.internal, seq]

    // Length encoding: if payload > 127 bytes, use extended 2-byte length
    if payload.count > 127 {
      let len = payload.count
      packet.append(UInt8((len >> 8) & 0x7F) | 0x80)
      packet.append(UInt8(len & 0xFF))
    } else {
      packet.append(UInt8(payload.count))
    }

    packet += payload
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
  }
}
