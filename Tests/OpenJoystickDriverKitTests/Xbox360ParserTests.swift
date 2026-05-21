import Foundation
import XCTest

@testable import OpenJoystickDriverKit

private func le16(_ value: Int16) -> (UInt8, UInt8) {
  let u = UInt16(bitPattern: value)
  return (UInt8(u & 0xFF), UInt8(u >> 8))
}

private func makeXbox360ReportLE(
  buttons: UInt16 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0,
  rsx: Int16 = 0,
  rsy: Int16 = 0
) -> Data {
  var r = [UInt8](repeating: 0, count: 20)
  r[0] = 0x00
  r[1] = 0x14
  r[2] = UInt8(buttons & 0xFF)
  r[3] = UInt8(buttons >> 8)
  r[4] = lt
  r[5] = rt
  let (lsxL, lsxH) = le16(lsx)
  let (lsyL, lsyH) = le16(lsy)
  let (rsxL, rsxH) = le16(rsx)
  let (rsyL, rsyH) = le16(rsy)
  r[6] = lsxL; r[7] = lsxH
  r[8] = lsyL; r[9] = lsyH
  r[10] = rsxL; r[11] = rsxH
  r[12] = rsyL; r[13] = rsyH
  return Data(r)
}

final class Xbox360ParserTests: XCTestCase {
  func testIgnoresNonInputReportType() throws {
    let parser = Xbox360Parser()
    // Type 0x08 = device connected notification on the wireless receiver
    let packet = Data([0x08, 0x14] + [UInt8](repeating: 0, count: 18))
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.isEmpty)
  }
  func testEmptyDataReturnsEmpty() throws {
    let parser = Xbox360Parser()
    let events = try parser.parse(data: Data())
    XCTAssertTrue(events.isEmpty)
  }
  func testShortReportReturnsEmpty() throws {
    let parser = Xbox360Parser()
    let packet = Data([0x00, 0x14, 0x00, 0x00, 0x00])
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.isEmpty)
  }
  func testInvalidLengthByteReturnsEmpty() throws {
    let parser = Xbox360Parser()
    var packet = [UInt8](makeXbox360ReportLE(buttons: 1 << 8))
    packet[1] = 0x0E
    let events = try parser.parse(data: Data(packet))
    XCTAssertTrue(events.isEmpty)
  }
  func testAllZeroReportReturnsNoSyntheticEvents() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE()
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.isEmpty)
  }
  func testAButtonPressRelease() throws {
    let parser = Xbox360Parser()
    // Bit 8 = A
    let press = makeXbox360ReportLE(buttons: 1 << 8)
    let release = makeXbox360ReportLE(buttons: 0)
    let pressEvents = try parser.parse(data: press)
    XCTAssertTrue(pressEvents.contains(.buttonPressed(.a)))
    let releaseEvents = try parser.parse(data: release)
    XCTAssertTrue(releaseEvents.contains(.buttonReleased(.a)))
  }
  func testBxyButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: (1 << 9) | (1 << 10) | (1 << 11))
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.contains(.buttonPressed(.b)))
    XCTAssertTrue(events.contains(.buttonPressed(.x)))
    XCTAssertTrue(events.contains(.buttonPressed(.y)))
  }
  func testShoulderAndStickClicks() throws {
    let parser = Xbox360Parser()
    // LB=bit12, RB=bit13, L3=bit6, R3=bit7
    let packet = makeXbox360ReportLE(buttons: (1 << 12) | (1 << 13) | (1 << 6) | (1 << 7))
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.contains(.buttonPressed(.leftBumper)))
    XCTAssertTrue(events.contains(.buttonPressed(.rightBumper)))
    XCTAssertTrue(events.contains(.buttonPressed(.leftStick)))
    XCTAssertTrue(events.contains(.buttonPressed(.rightStick)))
  }
  func testStartBackButtons() throws {
    let parser = Xbox360Parser()
    // START=bit4, BACK=bit5
    let packet = makeXbox360ReportLE(buttons: (1 << 4) | (1 << 5))
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.contains(.buttonPressed(.start)))
    XCTAssertTrue(events.contains(.buttonPressed(.back)))
  }
  func testGuideButton() throws {
    let parser = Xbox360Parser()
    // GUIDE=bit14
    let packet = makeXbox360ReportLE(buttons: 1 << 14)
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.contains(.buttonPressed(.guide)))
  }
  func testDpadDirections() throws {
    let parser = Xbox360Parser()
    // up=bit0, down=bit1, left=bit2, right=bit3
    func dpadEvent(bits: UInt16) throws -> ControllerEvent? {
      let events = try parser.parse(data: makeXbox360ReportLE(buttons: bits))
      // Reset to neutral for next test
      _ = try parser.parse(data: makeXbox360ReportLE(buttons: 0))
      return events.first { if case .dpadChanged = $0 { return true }; return false }
    }
    guard case .dpadChanged(let n) = try dpadEvent(bits: 1) else { XCTFail("no dpad"); return }
    XCTAssertTrue(n == .north)
    guard case .dpadChanged(let s) = try dpadEvent(bits: 2) else { XCTFail("no dpad"); return }
    XCTAssertTrue(s == .south)
    guard case .dpadChanged(let w) = try dpadEvent(bits: 4) else { XCTFail("no dpad"); return }
    XCTAssertTrue(w == .west)
    guard case .dpadChanged(let e) = try dpadEvent(bits: 8) else { XCTFail("no dpad"); return }
    XCTAssertTrue(e == .east)
    // northEast = up + right
    guard case .dpadChanged(let ne) = try dpadEvent(bits: 9) else { XCTFail("no dpad"); return }
    XCTAssertTrue(ne == .northEast)
  }
  func testDpadBitsNotFaceButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: 0x000F)  // all four dpad bits set
    let events = try parser.parse(data: packet)
    XCTAssertTrue(!events.contains(.buttonPressed(.a)))
    XCTAssertTrue(!events.contains(.buttonPressed(.b)))
    XCTAssertTrue(!events.contains(.buttonPressed(.x)))
    XCTAssertTrue(!events.contains(.buttonPressed(.y)))
  }
  func testTriggerNormalization() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lt: 255, rt: 255)
    let events = try parser.parse(data: packet)
    let lt = events.first { if case .leftTriggerChanged = $0 { return true }; return false }
    let rt = events.first { if case .rightTriggerChanged = $0 { return true }; return false }
    guard case .leftTriggerChanged(let ltVal) = lt else { XCTFail("no LT event"); return }
    guard case .rightTriggerChanged(let rtVal) = rt else { XCTFail("no RT event"); return }
    XCTAssertTrue(abs(ltVal - 1.0) < 0.01)
    XCTAssertTrue(abs(rtVal - 1.0) < 0.01)
  }
  func testTriggerHalfPress() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lt: 128, rt: 128)
    let events = try parser.parse(data: packet)
    let lt = events.first { if case .leftTriggerChanged = $0 { return true }; return false }
    guard case .leftTriggerChanged(let ltVal) = lt else { XCTFail("no LT event"); return }
    XCTAssertTrue(abs(ltVal - (128.0 / 255.0)) < 0.01)
  }
  func testLeftStickFullRight() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lsx: Int16.max)
    let events = try parser.parse(data: packet)
    let ls = events.first { if case .leftStickChanged = $0 { return true }; return false }
    guard case .leftStickChanged(let lx, _) = ls else { XCTFail("no LS event"); return }
    XCTAssertTrue(abs(lx - 1.0) < 0.01)
  }
  func testLeftStickFullUp() throws {
    let parser = Xbox360Parser()
    // Raw negative LSY = stick pushed up; normalized output should be positive Y
    let packet = makeXbox360ReportLE(lsy: Int16.min)
    let events = try parser.parse(data: packet)
    let ls = events.first { if case .leftStickChanged = $0 { return true }; return false }
    guard case .leftStickChanged(_, let ly) = ls else { XCTFail("no LS event"); return }
    XCTAssertTrue(ly == 1.0)
  }
  func testRightStickNormalization() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(rsx: Int16.min, rsy: Int16.max)
    let events = try parser.parse(data: packet)
    let rs = events.first { if case .rightStickChanged = $0 { return true }; return false }
    guard case .rightStickChanged(let rx, let ry) = rs else { XCTFail("no RS event"); return }
    XCTAssertTrue(rx == -1.0)
    // RSY raw positive = stick down → normalized output negative
    XCTAssertTrue(ry < -0.99)
  }
  func testChangeDetectionButtons() throws {
    let parser = Xbox360Parser()
    let press = makeXbox360ReportLE(buttons: 1 << 8)  // A
    _ = try parser.parse(data: press)
    let events2 = try parser.parse(data: press)
    XCTAssertTrue(!events2.contains(.buttonPressed(.a)))
    XCTAssertTrue(!events2.contains(.buttonReleased(.a)))
  }
  func testChangeDetectionTriggers() throws {
    let parser = Xbox360Parser()
    let first = makeXbox360ReportLE(lt: 200)
    _ = try parser.parse(data: first)
    let events2 = try parser.parse(data: first)
    let hasLT = events2.contains { if case .leftTriggerChanged = $0 { return true }; return false }
    XCTAssertTrue(!hasLT)
  }
  func testChangeDetectionSticks() throws {
    let parser = Xbox360Parser()
    let first = makeXbox360ReportLE(lsx: 10_000)
    _ = try parser.parse(data: first)
    let events2 = try parser.parse(data: first)
    let hasLS = events2.contains { if case .leftStickChanged = $0 { return true }; return false }
    XCTAssertTrue(!hasLS)
  }
  func testMultipleSimultaneousButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: (1 << 8) | (1 << 9) | (1 << 12))
    let events = try parser.parse(data: packet)
    XCTAssertTrue(events.contains(.buttonPressed(.a)))
    XCTAssertTrue(events.contains(.buttonPressed(.b)))
    XCTAssertTrue(events.contains(.buttonPressed(.leftBumper)))
  }
  func testIgnoresConnectionReport() throws {
    let parser = Xbox360Parser()
    var bytes = [UInt8](repeating: 0, count: 20)
    bytes[0] = 0x08  // connection notification
    let events = try parser.parse(data: Data(bytes))
    XCTAssertTrue(events.isEmpty)
  }
}
