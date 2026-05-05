import Testing

@testable import OpenJoystickDriverKit

/// Builds a 20-byte Xbox 360 wired input report from explicit field values.
private func makeXbox360Report(
  buttons: UInt16 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0,
  rsx: Int16 = 0,
  rsy: Int16 = 0
) -> [UInt8] {
  var r = [UInt8](repeating: 0, count: 20)
  r[0] = 0x00  // input report type
  r[1] = 0x14  // length = 20
  r[2] = UInt8(buttons & 0xFF)
  r[3] = UInt8(buttons >> 8)
  r[4] = lt
  r[5] = rt
  r[6] = UInt8(bitPattern: Int8(truncatingIfNeeded: lsx))
  r[7] = UInt8(bitPattern: Int8(truncatingIfNeeded: lsx >> 8))
  r[8] = UInt8(bitPattern: Int8(truncatingIfNeeded: lsy))
  r[9] = UInt8(bitPattern: Int8(truncatingIfNeeded: lsy >> 8))
  r[10] = UInt8(bitPattern: Int8(truncatingIfNeeded: rsx))
  r[11] = UInt8(bitPattern: Int8(truncatingIfNeeded: rsx >> 8))
  r[12] = UInt8(bitPattern: Int8(truncatingIfNeeded: rsy))
  r[13] = UInt8(bitPattern: Int8(truncatingIfNeeded: rsy >> 8))
  return r
}

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

@Suite("Xbox360 Parser Tests") struct Xbox360ParserTests {

  @Test("Non-input report type returns empty array")
  func ignoresNonInputReportType() throws {
    let parser = Xbox360Parser()
    // Type 0x08 = device connected notification on the wireless receiver
    let packet = Data([0x08, 0x14] + [UInt8](repeating: 0, count: 18))
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test("Empty data returns empty array")
  func emptyDataReturnsEmpty() throws {
    let parser = Xbox360Parser()
    let events = try parser.parse(data: Data())
    #expect(events.isEmpty)
  }

  @Test("Report shorter than minimum returns empty array")
  func shortReportReturnsEmpty() throws {
    let parser = Xbox360Parser()
    let packet = Data([0x00, 0x14, 0x00, 0x00, 0x00])
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test("All-zero input report fires initial left stick event")
  func allZeroReportFiresSticks() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE()
    let events = try parser.parse(data: packet)
    let hasLeft = events.contains {
      if case .leftStickChanged = $0 { return true }
      return false
    }
    #expect(hasLeft)
  }

  @Test("A button pressed and released")
  func aButtonPressRelease() throws {
    let parser = Xbox360Parser()
    // Bit 8 = A
    let press = makeXbox360ReportLE(buttons: 1 << 8)
    let release = makeXbox360ReportLE(buttons: 0)
    let pressEvents = try parser.parse(data: press)
    #expect(pressEvents.contains(.buttonPressed(.a)))
    let releaseEvents = try parser.parse(data: release)
    #expect(releaseEvents.contains(.buttonReleased(.a)))
  }

  @Test("B, X, Y buttons")
  func bxyButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: (1 << 9) | (1 << 10) | (1 << 11))
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.x)))
    #expect(events.contains(.buttonPressed(.y)))
  }

  @Test("Shoulder buttons and stick clicks")
  func shoulderAndStickClicks() throws {
    let parser = Xbox360Parser()
    // LB=bit12, RB=bit13, L3=bit6, R3=bit7
    let packet = makeXbox360ReportLE(buttons: (1 << 12) | (1 << 13) | (1 << 6) | (1 << 7))
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.buttonPressed(.rightBumper)))
    #expect(events.contains(.buttonPressed(.leftStick)))
    #expect(events.contains(.buttonPressed(.rightStick)))
  }

  @Test("Start and Back buttons")
  func startBackButtons() throws {
    let parser = Xbox360Parser()
    // START=bit4, BACK=bit5
    let packet = makeXbox360ReportLE(buttons: (1 << 4) | (1 << 5))
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.start)))
    #expect(events.contains(.buttonPressed(.back)))
  }

  @Test("Guide button")
  func guideButton() throws {
    let parser = Xbox360Parser()
    // GUIDE=bit14
    let packet = makeXbox360ReportLE(buttons: 1 << 14)
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.guide)))
  }

  @Test("D-pad directions")
  func dpadDirections() throws {
    let parser = Xbox360Parser()
    // up=bit0, down=bit1, left=bit2, right=bit3
    func dpadEvent(bits: UInt16) throws -> ControllerEvent? {
      let events = try parser.parse(data: makeXbox360ReportLE(buttons: bits))
      // Reset to neutral for next test
      _ = try parser.parse(data: makeXbox360ReportLE(buttons: 0))
      return events.first { if case .dpadChanged = $0 { return true }; return false }
    }
    guard case .dpadChanged(let n) = try dpadEvent(bits: 1) else { Issue.record("no dpad"); return }
    #expect(n == .north)
    guard case .dpadChanged(let s) = try dpadEvent(bits: 2) else { Issue.record("no dpad"); return }
    #expect(s == .south)
    guard case .dpadChanged(let w) = try dpadEvent(bits: 4) else { Issue.record("no dpad"); return }
    #expect(w == .west)
    guard case .dpadChanged(let e) = try dpadEvent(bits: 8) else { Issue.record("no dpad"); return }
    #expect(e == .east)
    // northEast = up + right
    guard case .dpadChanged(let ne) = try dpadEvent(bits: 9) else { Issue.record("no dpad"); return }
    #expect(ne == .northEast)
  }

  @Test("D-pad bits are not reported as face-button events")
  func dpadBitsNotFaceButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: 0x000F)  // all four dpad bits set
    let events = try parser.parse(data: packet)
    #expect(!events.contains(.buttonPressed(.a)))
    #expect(!events.contains(.buttonPressed(.b)))
    #expect(!events.contains(.buttonPressed(.x)))
    #expect(!events.contains(.buttonPressed(.y)))
  }

  @Test("Trigger normalization: full press = 1.0")
  func triggerNormalization() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lt: 255, rt: 255)
    let events = try parser.parse(data: packet)
    let lt = events.first { if case .leftTriggerChanged = $0 { return true }; return false }
    let rt = events.first { if case .rightTriggerChanged = $0 { return true }; return false }
    guard case .leftTriggerChanged(let ltVal) = lt else { Issue.record("no LT event"); return }
    guard case .rightTriggerChanged(let rtVal) = rt else { Issue.record("no RT event"); return }
    #expect(abs(ltVal - 1.0) < 0.01)
    #expect(abs(rtVal - 1.0) < 0.01)
  }

  @Test("Trigger normalization: half press ~= 0.5")
  func triggerHalfPress() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lt: 128, rt: 128)
    let events = try parser.parse(data: packet)
    let lt = events.first { if case .leftTriggerChanged = $0 { return true }; return false }
    guard case .leftTriggerChanged(let ltVal) = lt else { Issue.record("no LT event"); return }
    #expect(abs(ltVal - (128.0 / 255.0)) < 0.01)
  }

  @Test("Left stick full right = +1.0 X")
  func leftStickFullRight() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(lsx: Int16.max)
    let events = try parser.parse(data: packet)
    let ls = events.first { if case .leftStickChanged = $0 { return true }; return false }
    guard case .leftStickChanged(let lx, _) = ls else { Issue.record("no LS event"); return }
    #expect(abs(lx - 1.0) < 0.01)
  }

  @Test("Left stick full up = +1.0 Y (raw negative because Y is inverted)")
  func leftStickFullUp() throws {
    let parser = Xbox360Parser()
    // Raw negative LSY = stick pushed up; normalized output should be positive Y
    let packet = makeXbox360ReportLE(lsy: Int16.min)
    let events = try parser.parse(data: packet)
    let ls = events.first { if case .leftStickChanged = $0 { return true }; return false }
    guard case .leftStickChanged(_, let ly) = ls else { Issue.record("no LS event"); return }
    // -(-32768 / 32767) ≈ +1.0003
    #expect(ly > 0.99)
  }

  @Test("Right stick normalization")
  func rightStickNormalization() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(rsx: Int16.min, rsy: Int16.max)
    let events = try parser.parse(data: packet)
    let rs = events.first { if case .rightStickChanged = $0 { return true }; return false }
    guard case .rightStickChanged(let rx, let ry) = rs else { Issue.record("no RS event"); return }
    // RSX full left ≈ -1.0
    #expect(rx < -0.99)
    // RSY raw positive = stick down → normalized output negative
    #expect(ry < -0.99)
  }

  @Test("Change detection suppresses duplicate button events")
  func changeDetectionButtons() throws {
    let parser = Xbox360Parser()
    let press = makeXbox360ReportLE(buttons: 1 << 8)  // A
    _ = try parser.parse(data: press)
    let events2 = try parser.parse(data: press)
    #expect(!events2.contains(.buttonPressed(.a)))
    #expect(!events2.contains(.buttonReleased(.a)))
  }

  @Test("Change detection suppresses duplicate trigger events")
  func changeDetectionTriggers() throws {
    let parser = Xbox360Parser()
    let first = makeXbox360ReportLE(lt: 200)
    _ = try parser.parse(data: first)
    let events2 = try parser.parse(data: first)
    let hasLT = events2.contains { if case .leftTriggerChanged = $0 { return true }; return false }
    #expect(!hasLT)
  }

  @Test("Change detection suppresses duplicate stick events")
  func changeDetectionSticks() throws {
    let parser = Xbox360Parser()
    let first = makeXbox360ReportLE(lsx: 10_000)
    _ = try parser.parse(data: first)
    let events2 = try parser.parse(data: first)
    let hasLS = events2.contains { if case .leftStickChanged = $0 { return true }; return false }
    #expect(!hasLS)
  }

  @Test("Multiple simultaneous button changes are all reported")
  func multipleSimultaneousButtons() throws {
    let parser = Xbox360Parser()
    let packet = makeXbox360ReportLE(buttons: (1 << 8) | (1 << 9) | (1 << 12))
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.leftBumper)))
  }

  @Test("Parser ignores reports of type != 0x00")
  func ignoresConnectionReport() throws {
    let parser = Xbox360Parser()
    var bytes = [UInt8](repeating: 0, count: 20)
    bytes[0] = 0x08  // connection notification
    let events = try parser.parse(data: Data(bytes))
    #expect(events.isEmpty)
  }
}
