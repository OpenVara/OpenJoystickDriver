import Foundation
import SwiftUSB

private let ds4AxisCenter: Float = 128
private let ds4HatNeutral: UInt8 = 0xFF
private let ds4TriggerMax: Float = 255

/// Parser for Sony DualShock 4 controllers (USB HID, Report ID 0x01).
///
/// No handshake required — DS4 sends input reports automatically on USB connection.
public final class DS4Parser: InputParser, @unchecked Sendable {

  private enum ReportOffset {
    static let leftStickX: Int = 1
    static let leftStickY: Int = 2
    static let rightStickX: Int = 3
    static let rightStickY: Int = 4
    static let buttons0: Int = 5
    static let buttons1: Int = 6
    static let buttons2: Int = 7
    static let l2Trigger: Int = 8
    static let r2Trigger: Int = 9
  }

  private var prevFace: UInt8 = 0
  private var prevShoulders: UInt8 = 0
  private var prevSystem: UInt8 = 0
  private var prevHat: UInt8 = ds4HatNeutral
  private var prevL2: UInt8 = 0
  private var prevR2: UInt8 = 0
  private var prevLSX = UInt8(ds4AxisCenter)
  private var prevLSY = UInt8(ds4AxisCenter)
  private var prevRSX = UInt8(ds4AxisCenter)
  private var prevRSY = UInt8(ds4AxisCenter)

  /// Creates a new DS4Parser.
  public init() {}

  // swiftlint:disable async_without_await
  /// No-op; DS4 requires no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    // DS4 requires no handshake; protocol conformance.
  }
  // swiftlint:enable async_without_await

  /// Parses one DS4 HID input report and returns zero or more controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    guard data.count >= 10 else { return [] }
    let bytes = Array(data)
    var events: [ControllerEvent] = []

    let stickEvents = parseSticks(bytes: bytes)
    events.append(contentsOf: stickEvents.events)
    let (lsxRaw, lsyRaw, rsxRaw, rsyRaw) = stickEvents.raws

    let triggerEvents = parseTriggers(bytes: bytes)
    events.append(contentsOf: triggerEvents.events)
    let (l2, r2) = triggerEvents.values

    let dpadEvents = parseDpad(bytes: bytes)
    events.append(contentsOf: dpadEvents.events)
    let hat = dpadEvents.value

    let faceEvents = parseFaceButtons(bytes: bytes)
    events.append(contentsOf: faceEvents.events)
    let face = faceEvents.value

    let shoulderEvents = parseShoulderButtons(bytes: bytes)
    events.append(contentsOf: shoulderEvents.events)
    let shoulders = shoulderEvents.value

    let systemEvents = parseSystemButtons(bytes: bytes)
    events.append(contentsOf: systemEvents.events)
    let system = systemEvents.value

    prevFace = face
    prevShoulders = shoulders
    prevSystem = system
    prevHat = hat
    prevL2 = l2
    prevR2 = r2
    prevLSX = lsxRaw
    prevLSY = lsyRaw
    prevRSX = rsxRaw
    prevRSY = rsyRaw

    return events
  }

  private func parseSticks(bytes: [UInt8]) -> (
    events: [ControllerEvent], raws: (UInt8, UInt8, UInt8, UInt8)
  ) {
    let lsxRaw = bytes[ReportOffset.leftStickX]
    let lsyRaw = bytes[ReportOffset.leftStickY]
    let rsxRaw = bytes[ReportOffset.rightStickX]
    let rsyRaw = bytes[ReportOffset.rightStickY]
    var events: [ControllerEvent] = []
    if lsxRaw != prevLSX || lsyRaw != prevLSY {
      let lx = normalizeHID(lsxRaw)
      let ly = -normalizeHID(lsyRaw)
      events.append(.leftStickChanged(x: lx, y: ly))
    }
    if rsxRaw != prevRSX || rsyRaw != prevRSY {
      let rx = normalizeHID(rsxRaw)
      let ry = -normalizeHID(rsyRaw)
      events.append(.rightStickChanged(x: rx, y: ry))
    }
    return (events, (lsxRaw, lsyRaw, rsxRaw, rsyRaw))
  }

  private func parseTriggers(bytes: [UInt8]) -> (events: [ControllerEvent], values: (UInt8, UInt8))
  {
    let l2 = bytes[ReportOffset.l2Trigger]
    let r2 = bytes[ReportOffset.r2Trigger]
    var events: [ControllerEvent] = []
    if l2 != prevL2 { events.append(.leftTriggerChanged(Float(l2) / ds4TriggerMax)) }
    if r2 != prevR2 { events.append(.rightTriggerChanged(Float(r2) / ds4TriggerMax)) }
    return (events, (l2, r2))
  }

  private func parseDpad(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let hat = bytes[ReportOffset.buttons0] & 0x0F
    var events: [ControllerEvent] = []
    if hat != prevHat { events.append(.dpadChanged(mapHat(hat))) }
    return (events, hat)
  }

  private func parseFaceButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let face = bytes[ReportOffset.buttons0]
    let events = diffButtons(
      prev: prevFace,
      curr: face,
      mapping: [(0x10, .square), (0x20, .cross), (0x40, .circle), (0x80, .triangle)]
    )
    return (events, face)
  }

  private func parseShoulderButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let shoulders = bytes[ReportOffset.buttons1]
    let events = diffButtons(
      prev: prevShoulders,
      curr: shoulders,
      mapping: [
        (0x01, .l1), (0x02, .r1), (0x10, .share), (0x20, .options), (0x40, .leftStick),
        (0x80, .rightStick),
      ]
    )
    return (events, shoulders)
  }

  private func parseSystemButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let system = bytes[ReportOffset.buttons2]
    let events = diffButtons(
      prev: prevSystem,
      curr: system,
      mapping: [(0x01, .ps), (0x02, .touchpad)]
    )
    return (events, system)
  }

  private func normalizeHID(_ raw: UInt8) -> Float { (Float(raw) - ds4AxisCenter) / ds4AxisCenter }

  private func mapHat(_ hat: UInt8) -> DpadDirection {
    switch hat {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }
}
