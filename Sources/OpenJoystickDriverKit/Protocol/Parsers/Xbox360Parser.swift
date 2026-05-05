import Foundation
import SwiftUSB

/// Report type byte for Xbox 360 input reports.
private let xbox360InputReportType: UInt8 = 0x00
/// Expected length byte and minimum size for a wired Xbox 360 input report.
private let xbox360InputReportLengthByte: UInt8 = 0x14
private let xbox360InputReportLength = 20
/// Maximum value for a trigger axis (UInt8).
private let xbox360TriggerMax: Float = 255
/// Maximum positive value for a signed stick axis.
private let xbox360StickMax: Float = Float(Int16.max)

/// Xbox 360 LED pattern constants for `sendLED(_:handle:pattern:)`.
public enum Xbox360LEDPattern: UInt8, Sendable {
  case allOff = 0x00
  case allBlink = 0x01
  /// Player 1: flash then hold.
  case player1Flash = 0x02
  /// Player 2: flash then hold.
  case player2Flash = 0x03
  /// Player 3: flash then hold.
  case player3Flash = 0x04
  /// Player 4: flash then hold.
  case player4Flash = 0x05
  /// Player 1: steady on.
  case player1On = 0x06
  /// Player 2: steady on.
  case player2On = 0x07
  /// Player 3: steady on.
  case player3On = 0x08
  /// Player 4: steady on.
  case player4On = 0x09
  case rotate = 0x0A
  case blinkCurrent = 0x0B
  case slowBlinkCurrent = 0x0C
  case rotateTwo = 0x0D
  case blinkAll = 0x0E
  case blinkOnceThenRestore = 0x0F
}

/// Parser for Xbox 360 wired controllers (vendor-specific USB class 0xFF, interface 0).
///
/// No handshake is required: the controller begins sending 20-byte input reports
/// immediately after the interface is claimed.
///
/// Input report layout (20 bytes, interrupt IN, EP 0x81):
/// ```
///   byte 0   : report type (0x00 = input; ignore others)
///   byte 1   : payload length (0x14 = 20)
///   bytes 2-3: button bitmask (UInt16 LE)
///              bit 0  DPAD_UP      bit 8  A
///              bit 1  DPAD_DOWN    bit 9  B
///              bit 2  DPAD_LEFT    bit 10 X
///              bit 3  DPAD_RIGHT   bit 11 Y
///              bit 4  START        bit 12 LB
///              bit 5  BACK         bit 13 RB
///              bit 6  L3           bit 14 GUIDE
///              bit 7  R3
///   byte 4   : LT (0–255)
///   byte 5   : RT (0–255)
///   bytes 6-7: Left stick X  (Int16 LE)
///   bytes 8-9: Left stick Y  (Int16 LE, positive = down; inverted on output)
///   bytes 10-11: Right stick X (Int16 LE)
///   bytes 12-13: Right stick Y (Int16 LE, positive = down; inverted on output)
///   bytes 14-19: unused
/// ```
///
/// Rumble output report (8 bytes, interrupt OUT, EP 0x01):
/// ```
///   byte 0 : 0x00 (report type)
///   byte 1 : 0x08 (length)
///   byte 2 : 0x00 (reserved)
///   byte 3 : left motor (0–255)
///   byte 4 : right motor (0–255)
///   bytes 5-7 : 0x00 padding
/// ```
///
/// LED output report (3 bytes, interrupt OUT, EP 0x01):
/// ```
///   byte 0 : 0x01 (LED command)
///   byte 1 : 0x03 (length)
///   byte 2 : LED pattern (see Xbox360LEDPattern)
/// ```
public final class Xbox360Parser: InputParser, @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All mutable state (prevButtons, prevLT/RT, prevLS/RS) is accessed
  //   exclusively from the owning DevicePipeline actor — no concurrent access.

  private let outEndpoint: UInt8

  private var prevButtons: UInt16 = 0
  private var prevLT: UInt8 = 0
  private var prevRT: UInt8 = 0
  private var prevLSX: Int16 = 0
  private var prevLSY: Int16 = 0
  private var prevRSX: Int16 = 0
  private var prevRSY: Int16 = 0

  /// Creates a new Xbox360Parser.
  /// - Parameter outEndpoint: Interrupt OUT endpoint address (default 0x01).
  public init(outEndpoint: UInt8 = 0x01) {
    self.outEndpoint = outEndpoint
  }

  // MARK: - InputParser

  // swiftlint:disable async_without_await
  /// No-op — Xbox 360 requires no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    // Xbox 360 starts sending input reports immediately after interface claim.
  }
  // swiftlint:enable async_without_await

  /// Parses one Xbox 360 input report and returns zero or more controller events.
  ///
  /// Silently ignores non-input report types (e.g. connection/disconnection events
  /// on the wireless receiver). Returns an empty array for reports that carry no
  /// state change since the previous call.
  public func parse(data: Data) throws -> [ControllerEvent] {
    guard !data.isEmpty, data[0] == xbox360InputReportType else { return [] }
    guard data.count >= xbox360InputReportLength, data[1] == xbox360InputReportLengthByte else {
      return []
    }
    let bytes = Array(data)

    let buttons = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
    let lt = bytes[4]
    let rt = bytes[5]
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))

    var events: [ControllerEvent] = []
    events += parseButtons(curr: buttons)
    events += parseDpad(curr: buttons)
    events += parseTriggers(lt: lt, rt: rt)
    events += parseSticks(lsx: lsx, lsy: lsy, rsx: rsx, rsy: rsy)

    prevButtons = buttons
    prevLT = lt
    prevRT = rt
    prevLSX = lsx
    prevLSY = lsy
    prevRSX = rsx
    prevRSY = rsy

    return events
  }

  // MARK: - Output

  /// Sends a rumble command to the physical controller.
  ///
  /// Xbox 360 has two motors only (no trigger haptics).
  /// - Parameters:
  ///   - handle: Active USB device handle.
  ///   - left: Left (strong) motor intensity (0–255).
  ///   - right: Right (weak) motor intensity (0–255).
  public func sendRumble(handle: USBDeviceHandle, left: UInt8, right: UInt8) throws {
    let packet: [UInt8] = [0x00, 0x08, 0x00, left, right, 0x00, 0x00, 0x00]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
  }

  /// Sets the ring-of-light LED pattern on the physical controller.
  ///
  /// - Parameters:
  ///   - handle: Active USB device handle.
  ///   - pattern: One of the ``Xbox360LEDPattern`` values.
  public func sendLED(handle: USBDeviceHandle, pattern: Xbox360LEDPattern) throws {
    let packet: [UInt8] = [0x01, 0x03, pattern.rawValue]
    _ = try handle.interruptTransfer(endpoint: outEndpoint, data: packet, timeout: 2000)
  }

  // MARK: - Private parsing

  private func parseButtons(curr: UInt16) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let changed = curr ^ prevButtons

    func check(_ bit: Int, _ button: Button) {
      let mask = UInt16(1 << bit)
      guard changed & mask != 0 else { return }
      events.append((curr & mask) != 0 ? .buttonPressed(button) : .buttonReleased(button))
    }

    check(4, .start)
    check(5, .back)
    check(6, .leftStick)
    check(7, .rightStick)
    check(8, .a)
    check(9, .b)
    check(10, .x)
    check(11, .y)
    check(12, .leftBumper)
    check(13, .rightBumper)
    check(14, .guide)

    return events
  }

  private func parseDpad(curr: UInt16) -> [ControllerEvent] {
    let dpadMask: UInt16 = 0x000F
    let currDpad = curr & dpadMask
    let prevDpad = prevButtons & dpadMask
    guard currDpad != prevDpad else { return [] }
    return [.dpadChanged(mapDpad(currDpad))]
  }

  private func parseTriggers(lt: UInt8, rt: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if lt != prevLT {
      events.append(.leftTriggerChanged(Float(lt) / xbox360TriggerMax))
    }
    if rt != prevRT {
      events.append(.rightTriggerChanged(Float(rt) / xbox360TriggerMax))
    }
    return events
  }

  private func parseSticks(lsx: Int16, lsy: Int16, rsx: Int16, rsy: Int16) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if lsx != prevLSX || lsy != prevLSY {
      events.append(.leftStickChanged(x: normalizeStick(lsx), y: -normalizeStick(lsy)))
    }
    if rsx != prevRSX || rsy != prevRSY {
      events.append(.rightStickChanged(x: normalizeStick(rsx), y: -normalizeStick(rsy)))
    }
    return events
  }

  private func normalizeStick(_ raw: Int16) -> Float {
    if raw == Int16.min { return -1.0 }
    return Float(raw) / xbox360StickMax
  }

  private func mapDpad(_ value: UInt16) -> DpadDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast   // up + right
    case 5: .northWest   // up + left
    case 10: .southEast  // down + right
    case 6: .southWest   // down + left
    default: .neutral
    }
  }
}
