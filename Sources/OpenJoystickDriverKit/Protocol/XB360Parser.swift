import Foundation
import SwiftUSB

private let xb360StickMax: Float = 32767
private let xb360TriggerMax: Float = 255

/// Parser for Xbox 360 wired controllers (USB class 0xFF, 20-byte input reports).
///
/// No handshake required — the controller sends input immediately on USB enumeration.
/// Protocol reference: Linux xpad.c `xpad360_process_packet`.
public final class XB360Parser: InputParser, @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All mutable state is accessed exclusively from the owning
  //   DevicePipeline actor — no concurrent access occurs

  private enum ReportOffset {
    static let buttons0 = 2
    static let buttons1 = 3
    static let leftTrigger = 4
    static let rightTrigger = 5
    static let leftStickX = 6
    static let leftStickY = 8
    static let rightStickX = 10
    static let rightStickY = 12
  }

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevLT: UInt8 = 0
  private var prevRT: UInt8 = 0
  private var prevLSX: Int16 = 0
  private var prevLSY: Int16 = 0
  private var prevRSX: Int16 = 0
  private var prevRSY: Int16 = 0

  /// Creates a new XB360Parser.
  public init() {}

  // swiftlint:disable async_without_await
  /// No-op; Xbox 360 controllers require no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {}
  // swiftlint:enable async_without_await

  /// Parses one Xbox 360 20-byte input report into controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    guard data.count >= 14, data[0] == 0x00 else { return [] }
    let bytes = Array(data)
    var events: [ControllerEvent] = []

    let stickEvents = parseSticks(bytes: bytes)
    events.append(contentsOf: stickEvents.events)

    let triggerEvents = parseTriggers(bytes: bytes)
    events.append(contentsOf: triggerEvents.events)

    let dpadEvents = parseDpad(bytes: bytes)
    events.append(contentsOf: dpadEvents.events)

    events += diffButtons(
      prev: prevButtons0,
      curr: bytes[ReportOffset.buttons0],
      mapping: [(0x10, .start), (0x20, .back), (0x40, .leftStick), (0x80, .rightStick)]
    )
    events += diffButtons(
      prev: prevButtons1,
      curr: bytes[ReportOffset.buttons1],
      mapping: [
        (0x01, .leftBumper), (0x02, .rightBumper), (0x04, .guide), (0x10, .a), (0x20, .b),
        (0x40, .x), (0x80, .y),
      ]
    )

    prevButtons0 = bytes[ReportOffset.buttons0]
    prevButtons1 = bytes[ReportOffset.buttons1]

    return events
  }

  // MARK: - Stick parsing

  private func parseSticks(bytes: [UInt8]) -> (events: [ControllerEvent], Void) {
    var events: [ControllerEvent] = []
    let lsx = readInt16LE(bytes, at: ReportOffset.leftStickX)
    let lsy = readInt16LE(bytes, at: ReportOffset.leftStickY)
    if lsx != prevLSX || lsy != prevLSY {
      events.append(
        .leftStickChanged(x: Float(lsx) / xb360StickMax, y: -(Float(lsy) / xb360StickMax))
      )
      prevLSX = lsx
      prevLSY = lsy
    }

    let rsx = readInt16LE(bytes, at: ReportOffset.rightStickX)
    let rsy = readInt16LE(bytes, at: ReportOffset.rightStickY)
    if rsx != prevRSX || rsy != prevRSY {
      events.append(
        .rightStickChanged(x: Float(rsx) / xb360StickMax, y: -(Float(rsy) / xb360StickMax))
      )
      prevRSX = rsx
      prevRSY = rsy
    }

    return (events, ())
  }

  // MARK: - Trigger parsing

  private func parseTriggers(bytes: [UInt8]) -> (events: [ControllerEvent], Void) {
    var events: [ControllerEvent] = []
    let lt = bytes[ReportOffset.leftTrigger]
    let rt = bytes[ReportOffset.rightTrigger]
    if lt != prevLT {
      events.append(.leftTriggerChanged(Float(lt) / xb360TriggerMax))
      prevLT = lt
    }
    if rt != prevRT {
      events.append(.rightTriggerChanged(Float(rt) / xb360TriggerMax))
      prevRT = rt
    }
    return (events, ())
  }

  // MARK: - D-pad parsing

  private func parseDpad(bytes: [UInt8]) -> (events: [ControllerEvent], Void) {
    let dpadBits = bytes[ReportOffset.buttons0] & 0x0F
    let prevDpadBits = prevButtons0 & 0x0F
    if dpadBits != prevDpadBits { return ([.dpadChanged(mapDpad(dpadBits))], ()) }
    return ([], ())
  }

  private func mapDpad(_ bits: UInt8) -> DpadDirection {
    switch bits {
    case 0x01: .north
    case 0x02: .south
    case 0x04: .west
    case 0x08: .east
    case 0x09: .northEast
    case 0x05: .northWest
    case 0x0A: .southEast
    case 0x06: .southWest
    default: .neutral
    }
  }

  // MARK: - Byte helpers

  private func readInt16LE(_ bytes: [UInt8], at offset: Int) -> Int16 {
    Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
  }
}
