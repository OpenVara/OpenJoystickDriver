import Foundation
import SwiftUSB

private let gipDpadMask: UInt8 = 0x0F
private let gipGuideButtonMask: UInt8 = 0x03
private let gipHandshakeMaxAttempts = 3
private let gipHandshakeRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
private let gipInitDelayNanoseconds: UInt64 = 50_000_000
private let gipStickMax: Float = 32767
private let gipTriggerMax: Float = 1023
/// GIP CMD=0x03 keep-alive sent to prevent controller idling (~4 s interval).
private let gipKeepAliveCmd: UInt8 = 0x03

/// Errors that ``GIPParser`` can throw during the handshake or while parsing packets.
public enum GIPError: Error, Sendable {
  /// The controller did not complete the handshake within the allowed number of attempts.
  case handshakeTimeout
  /// The handshake failed for a specific reason (e.g. no USB handle was provided).
  case handshakeFailed(String)
  /// A received packet is too short or its declared length does not match the actual data.
  case malformedPacket(String)
}

/// Parser for Xbox One (GIP) controllers connected over USB.
///
/// Sends the three-packet GIP init sequence on connection, then parses
/// incoming interrupt-transfer packets into ``ControllerEvent`` values.
/// Sends a keep-alive ping every ~4 seconds to prevent the controller
/// from entering idle.
public final class GIPParser: InputParser, @unchecked Sendable {

  private enum Command {
    static let power: UInt8 = 0x05
    static let authInit: UInt8 = 0x06
    static let ledInit: UInt8 = 0x0A
  }

  private enum Option { static let `internal`: UInt8 = 0x20 }

  private enum CMD {
    static let input: UInt8 = 0x20
    static let virtualKey: UInt8 = 0x07
  }

  private let outEndpoint: UInt8 = 0x02

  private var sequencer = GIPSequencer()

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevExtButtons: UInt8 = 0
  private var prevLT: UInt16 = 0
  private var prevRT: UInt16 = 0

  public init() {}

  // MARK: - InputParser

  public func performHandshake(handle: USBDeviceHandle?) async throws {
    guard let handle else {
      throw GIPError.handshakeFailed("No USB handle provided for GIP handshake")
    }
    for attempt in 0..<gipHandshakeMaxAttempts {
      do {
        try await sendInitSequence(handle: handle)
        print("[GIPParser] Init sequence sent" + " (attempt \(attempt + 1))")
        return
      } catch {
        print("[GIPParser] Init attempt \(attempt + 1) " + "failed: \(error)")
        guard attempt < gipHandshakeMaxAttempts - 1 else { throw GIPError.handshakeTimeout }
        try await Task.sleep(nanoseconds: gipHandshakeRetryDelays[attempt])
      }
    }
  }

  /// Send GIP keep-alive (CMD=0x03) to prevent the controller entering idle.
  public func keepAlive(handle: USBDeviceHandle?) throws {
    guard let handle else { return }
    let seq = sequencer.next(for: gipKeepAliveCmd)
    let packet: [UInt8] = [gipKeepAliveCmd, Option.internal, seq, 3, 0x00, 0x00, 0x00]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
  }

  public func parse(data: Data) throws -> [ControllerEvent] {
    guard data.count >= 4 else {
      throw GIPError.malformedPacket("Packet too short: \(data.count) bytes")
    }
    let payloadLength = Int(data[3])
    guard data.count >= 4 + payloadLength else {
      throw GIPError.malformedPacket(
        "Packet shorter than declared payload: " + "\(data.count) < \(4 + payloadLength)"
      )
    }
    let payload = data.dropFirst(4).prefix(payloadLength)

    switch data[0] {
    case CMD.input: return parseMainInput(payload: Data(payload))
    case CMD.virtualKey: return parseGuideButton(payload: Data(payload))
    default: return []
    }
  }

  // MARK: - Private

  /// Send full 3-packet GIP init sequence:
  /// power-on, LED init, auth/announce init.
  /// 50ms delay between packets per GIP spec.
  private func sendInitSequence(handle: USBDeviceHandle) async throws {
    let initDelay = gipInitDelayNanoseconds

    try sendPowerOnPacket(handle: handle)
    try await Task.sleep(nanoseconds: initDelay)

    try sendLedInitPacket(handle: handle)
    try await Task.sleep(nanoseconds: initDelay)

    try sendAuthInitPacket(handle: handle)
  }

  private func sendPowerOnPacket(handle: USBDeviceHandle) throws {
    let powerSeq = sequencer.next(for: Command.power)
    let powerPacket: [UInt8] = [Command.power, Option.internal, powerSeq, 1, 0]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: powerPacket, timeout: 2000)
  }

  private func sendLedInitPacket(handle: USBDeviceHandle) throws {
    let ledSeq = sequencer.next(for: Command.ledInit)
    let ledPacket: [UInt8] = [Command.ledInit, Option.internal, ledSeq, 3, 0x00, 0x01, 0x14]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: ledPacket, timeout: 2000)
  }

  private func sendAuthInitPacket(handle: USBDeviceHandle) throws {
    let authSeq = sequencer.next(for: Command.authInit)
    let authPacket: [UInt8] = [Command.authInit, Option.internal, authSeq, 2, 0x01, 0x00]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: authPacket, timeout: 2000)
  }

  private func parseMainInput(payload: Data) -> [ControllerEvent] {
    guard payload.count >= 14 else {
      print("[GIPParser] Main input payload too short: " + "\(payload.count)")
      return []
    }
    let bytes = Array(payload)

    let buttons0 = bytes[0]
    let buttons1 = bytes[1]
    let lt = parseLT(from: bytes)
    let rt = parseRT(from: bytes)
    let (lsx, lsy, rsx, rsy) = parseSticks(from: bytes)

    var events: [ControllerEvent] = []
    events += parseFaceButtons(curr: buttons0)
    events += parseShoulderButtons(curr: buttons1)
    events += parseDpad(curr: buttons1)
    events += parseSticksEvents(lsx: lsx, lsy: lsy, rsx: rsx, rsy: rsy)
    events += parseTriggers(lt: lt, rt: rt)

    if bytes.count >= 15 { events += parseExtendedButtons(extByte: bytes[14]) }

    prevButtons0 = buttons0
    prevButtons1 = buttons1
    prevExtButtons = bytes.count >= 15 ? bytes[14] : prevExtButtons
    prevLT = lt
    prevRT = rt

    return events
  }

  private func parseLT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[2]) | (UInt16(bytes[3]) << 8) }

  private func parseRT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[4]) | (UInt16(bytes[5]) << 8) }

  private func parseSticks(from bytes: [UInt8]) -> (Int16, Int16, Int16, Int16) {
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    return (lsx, lsy, rsx, rsy)
  }

  private func parseFaceButtons(curr: UInt8) -> [ControllerEvent] {
    diffButtons(
      prev: prevButtons0,
      curr: curr,
      mapping: [(4, .start), (8, .back), (16, .a), (32, .b), (64, .x), (128, .y)]
    )
  }

  private func parseShoulderButtons(curr: UInt8) -> [ControllerEvent] {
    diffButtons(
      prev: prevButtons1,
      curr: curr,
      mapping: [(16, .leftBumper), (32, .rightBumper), (64, .leftStick), (128, .rightStick)]
    )
  }

  private func parseDpad(curr: UInt8) -> [ControllerEvent] {
    let dpad = curr & gipDpadMask
    let prevDpad = prevButtons1 & gipDpadMask
    if dpad != prevDpad { return [.dpadChanged(mapDpad(dpad))] }
    return []
  }

  private func parseSticksEvents(lsx: Int16, lsy: Int16, rsx: Int16, rsy: Int16)
    -> [ControllerEvent]
  {
    let lx = normalizeStick(lsx)
    let ly = -normalizeStick(lsy)
    let rx = normalizeStick(rsx)
    let ry = -normalizeStick(rsy)
    return [.leftStickChanged(x: lx, y: ly), .rightStickChanged(x: rx, y: ry)]
  }

  private func parseTriggers(lt: UInt16, rt: UInt16) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if lt != prevLT { events.append(.leftTriggerChanged(Float(lt) / gipTriggerMax)) }
    if rt != prevRT { events.append(.rightTriggerChanged(Float(rt) / gipTriggerMax)) }
    return events
  }

  private func parseGuideButton(payload: Data) -> [ControllerEvent] {
    guard let first = payload.first else { return [] }
    if (first & gipGuideButtonMask) != 0 { return [.buttonPressed(.guide)] }
    return [.buttonReleased(.guide)]
  }

  /// Parse extended button byte present in G7 SE 32-byte INPUT payload at offset 14.
  /// Confirmed: bit 0x01 = Share.
  private func parseExtendedButtons(extByte: UInt8) -> [ControllerEvent] {
    diffButtons(prev: prevExtButtons, curr: extByte, mapping: [(1, .share)])
  }

  private func diffButtons(prev: UInt8, curr: UInt8, mapping: [(UInt8, Button)])
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    for (bit, button) in mapping {
      let wasPressed = (prev & bit) != 0
      let isPressed = (curr & bit) != 0
      if !wasPressed && isPressed {
        events.append(.buttonPressed(button))
      } else if wasPressed && !isPressed {
        events.append(.buttonReleased(button))
      }
    }
    return events
  }

  private func normalizeStick(_ raw: Int16) -> Float { Float(raw) / gipStickMax }

  private func mapDpad(_ value: UInt8) -> DpadDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast  // up + right
    case 5: .northWest  // up + left
    case 10: .southEast  // down + right
    case 6: .southWest  // down + left
    default: .neutral
    }
  }
}
