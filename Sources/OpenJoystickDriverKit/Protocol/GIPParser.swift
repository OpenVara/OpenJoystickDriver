import Foundation
import SwiftUSB

private let gipDpadMask: UInt8 = 0x0F
private let gipGuideButtonMask: UInt8 = 0x03
private let gipHandshakeMaxAttempts = 3
private let gipHandshakeRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
private let gipInitDelayNanoseconds: UInt64 = 50_000_000
private let gipStickMax: Float = 32767
private let gipTriggerMax: Float = 1023

/// Errors that ``GIPParser`` can throw during the handshake or while parsing packets.
public enum GIPError: Error, Sendable {
  /// The controller did not complete the handshake within the allowed number of attempts.
  case handshakeTimeout
  /// The handshake failed for a specific reason (e.g. no USB handle was provided).
  case handshakeFailed(String)
  /// A received packet is too short or its declared length does not match the actual data.
  case malformedPacket(String)
  /// Authentication sub-protocol error.
  case authFailed(String)
}

/// Parser for Xbox One (GIP) controllers connected over USB.
///
/// Sends the three-packet GIP init sequence on connection, then parses
/// incoming interrupt-transfer packets into ``ControllerEvent`` values.
/// Sends a keep-alive ping every ~4 seconds to prevent the controller
/// from entering idle.
public final class GIPParser: InputParser, @unchecked Sendable {

  private let outEndpoint: UInt8 = 0x02

  private var sequencer = GIPSequencer()
  private let authHandler = GIPAuthHandler()
  private var handle: USBDeviceHandle?

  /// Current device state, driven by auth progress.
  public var deviceState: GIPDeviceState { authHandler.deviceState }

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevLT: UInt16 = 0
  private var prevRT: UInt16 = 0
  private var prevLSX: Int16 = 0
  private var prevLSY: Int16 = 0
  private var prevRSX: Int16 = 0
  private var prevRSY: Int16 = 0

  /// Creates a new GIPParser.
  public init() {}

  // MARK: - InputParser

  /// Sends the GIP init sequence to the controller.
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    guard let handle else {
      throw GIPError.handshakeFailed("No USB handle provided for GIP handshake")
    }
    self.handle = handle
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
    let seq = sequencer.next(for: GIPCommand.keepAlive)
    let packet: [UInt8] = [GIPCommand.keepAlive, GIPOption.internal, seq, 3, 0x00, 0x00, 0x00]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
  }

  /// Parses one GIP packet and returns zero or more controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    guard data.count >= 4 else {
      throw GIPError.malformedPacket("Packet too short: \(data.count) bytes")
    }

    // Parse payload length — extended encoding when bit 7 is set on byte 3
    let payloadLength: Int
    let headerSize: Int
    if data[3] & 0x80 != 0 {
      guard data.count >= 5 else {
        throw GIPError.malformedPacket("Extended length but packet too short")
      }
      payloadLength = Int(data[3] & 0x7F) << 8 | Int(data[4])
      headerSize = 5
    } else {
      payloadLength = Int(data[3])
      headerSize = 4
    }

    guard data.count >= headerSize + payloadLength else {
      throw GIPError.malformedPacket(
        "Packet shorter than declared payload: " + "\(data.count) < \(headerSize + payloadLength)"
      )
    }
    let payload = data.dropFirst(headerSize).prefix(payloadLength)

    switch data[0] {
    case GIPCommand.input: return parseMainInput(payload: Data(payload))
    case GIPCommand.virtualKey: return parseGuideButton(payload: Data(payload))
    case GIPCommand.authenticate:
      if let handle {
        do {
          try authHandler.handleAuthMessage(
            payload: Data(payload),
            handle: handle,
            sequencer: &sequencer
          )
        } catch { print("[GIPParser] Auth error: \(error)") }
      }
      return []
    default: return []
    }
  }

  /// Sends a GIP rumble command (CMD=0x09) to the physical controller.
  ///
  /// - Parameters:
  ///   - handle: Active USB device handle for the physical controller.
  ///   - left: Left main motor intensity (0–255).
  ///   - right: Right main motor intensity (0–255).
  ///   - ltMotor: Left trigger motor intensity (0–255).
  ///   - rtMotor: Right trigger motor intensity (0–255).
  public func sendRumble(
    handle: USBDeviceHandle,
    left: UInt8,
    right: UInt8,
    ltMotor: UInt8,
    rtMotor: UInt8
  ) throws {
    let seq = sequencer.next(for: GIPCommand.rumble)
    let activation: UInt8 = 0x0F  // all four motors
    let packet: [UInt8] = [
      GIPCommand.rumble, GIPOption.internal, seq, 0x09, 0x00, activation, ltMotor, rtMotor, left,
      right, 0x20, 0x00, 0x00,  // duration=32, delay=0, repeat=0
    ]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
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
    let powerSeq = sequencer.next(for: GIPCommand.power)
    let powerPacket: [UInt8] = [GIPCommand.power, GIPOption.internal, powerSeq, 1, 0]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: powerPacket, timeout: 2000)
  }

  private func sendLedInitPacket(handle: USBDeviceHandle) throws {
    let ledSeq = sequencer.next(for: GIPCommand.led)
    let ledPacket: [UInt8] = [GIPCommand.led, GIPOption.internal, ledSeq, 3, 0x00, 0x01, 0x14]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: ledPacket, timeout: 2000)
  }

  private func sendAuthInitPacket(handle: USBDeviceHandle) throws {
    let authSeq = sequencer.next(for: GIPCommand.authenticate)
    let authPacket: [UInt8] = [GIPCommand.authenticate, GIPOption.internal, authSeq, 2, 0x01, 0x00]
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

    prevButtons0 = buttons0
    prevButtons1 = buttons1
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
    var events: [ControllerEvent] = []
    if lsx != prevLSX || lsy != prevLSY {
      let lx = normalizeStick(lsx)
      let ly = -normalizeStick(lsy)
      events.append(.leftStickChanged(x: lx, y: ly))
      prevLSX = lsx
      prevLSY = lsy
    }
    if rsx != prevRSX || rsy != prevRSY {
      let rx = normalizeStick(rsx)
      let ry = -normalizeStick(rsy)
      events.append(.rightStickChanged(x: rx, y: ry))
      prevRSX = rsx
      prevRSY = rsy
    }
    return events
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
