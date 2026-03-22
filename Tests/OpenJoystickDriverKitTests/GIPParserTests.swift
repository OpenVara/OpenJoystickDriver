import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("GIP Parser Tests") struct GIPParserTests {

  @Test func sequencerIncrements() {
    var seq = GIPSequencer()
    #expect(seq.next(for: 5) == 0)
    #expect(seq.next(for: 5) == 1)
    // Different command starts at 0
    #expect(seq.next(for: 32) == 0)
    // Original command continues
    #expect(seq.next(for: 5) == 2)
  }

  @Test func sequencerWrapsAt255() {
    var seq = GIPSequencer()
    for _ in 0..<255 { _ = seq.next(for: 1) }
    #expect(seq.next(for: 1) == 255)
    #expect(seq.next(for: 1) == 0)
  }

  @Test func sequencerReset() {
    var seq = GIPSequencer()
    _ = seq.next(for: 5)
    _ = seq.next(for: 5)
    seq.reset(commandID: 5)
    #expect(seq.next(for: 5) == 0)
  }

  @Test func parseMainInputAllZeroEmitsNoStickEvents() throws {
    let parser = GIPParser()
    var packet = Data([0x20, 32, 0, 14])
    packet += Data(repeating: 0, count: 14)
    let events = try parser.parse(data: packet)
    let hasStick = events.contains {
      if case .leftStickChanged = $0 { return true }
      if case .rightStickChanged = $0 { return true }
      return false
    }
    #expect(!hasStick)
  }

  @Test func parseMainInputAButton() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    payload[0] = 16  // A button
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.a)))
  }

  @Test func parseMainInputMultipleButtons() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // buttons0: A(16) + B(32) = 48
    payload[0] = 48
    // buttons1: LB(16) + dpad_up(1) = 17
    payload[1] = 17
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.dpadChanged(.north)))
  }

  @Test func unknownCMDReturnsEmpty() throws {
    let parser = GIPParser()
    let packet = Data([3, 32, 1, 4, 32, 0, 0, 0])
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test func parseGuideButtonPressed() throws {
    let parser = GIPParser()
    let packet = Data([7, 32, 0, 1, 1])
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonPressed(.guide)))
  }

  @Test func parseGuideButtonReleased() throws {
    let parser = GIPParser()
    let packet = Data([7, 32, 0, 1, 0])
    let events = try parser.parse(data: packet)
    #expect(events.contains(.buttonReleased(.guide)))
  }

  @Test func parseShortPacketThrows() {
    let parser = GIPParser()
    #expect(throws: (any Error).self) { try parser.parse(data: Data([2, 32])) }
  }

  @Test func parseMalformedLengthThrows() {
    let parser = GIPParser()
    #expect(throws: (any Error).self) { try parser.parse(data: Data([2, 32, 0, 14, 0, 0])) }
  }

  @Test func triggerNormalization() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // LT = 1023 (max) = 0x03FF LE
    payload[2] = 0xFF  // LT low byte
    payload[3] = 0x03  // LT high byte
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    let ltEvent = events.first {
      if case .leftTriggerChanged = $0 { return true }
      return false
    }
    guard case .leftTriggerChanged(let ltVal) = ltEvent else {
      Issue.record("No leftTriggerChanged event")
      return
    }
    #expect(abs(ltVal - 1.0) < 0.01)
  }

  @Test func stickNormalization() throws {
    let parser = GIPParser()
    var payload = Data(repeating: 0, count: 14)
    // LSX = Int16(-32768) = full left -> lx ~ -1.0
    payload[6] = 0x00
    payload[7] = 0x80
    // LSY = Int16(-32768) -> ly = -(-32768/32767) ~ +1.0
    payload[8] = 0x00
    payload[9] = 0x80
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    let lsEvent = events.first {
      if case .leftStickChanged = $0 { return true }
      return false
    }
    guard case .leftStickChanged(let lx, let ly) = lsEvent else {
      Issue.record("No leftStickChanged event")
      return
    }
    #expect(abs(lx - (-1.0)) < 0.01)
    #expect(abs(ly - 1.0) < 0.01)
  }

  @Test func dpadCombinations() throws {
    let parser = GIPParser()
    // up+right = 1+8 = 9
    var payload = Data(repeating: 0, count: 14)
    payload[1] = 9
    var packet = Data([0x20, 32, 0, 14])
    packet += payload
    let events = try parser.parse(data: packet)
    #expect(events.contains(.dpadChanged(.northEast)))
  }

  @Test func unhandledReportTypeReturnsEmpty() throws {
    let parser = GIPParser()
    let packet = Data([99, 32, 0, 2, 0, 0])
    let events = try parser.parse(data: packet)
    #expect(events.isEmpty)
  }

  @Test func changeDetectionSuppressesDuplicates() throws {
    let parser = GIPParser()
    var payload1 = Data(repeating: 0, count: 14)
    payload1[0] = 16  // A
    var packet1 = Data([0x20, 32, 0, 14])
    packet1 += payload1
    let events1 = try parser.parse(data: packet1)
    #expect(events1.contains(.buttonPressed(.a)))

    // Same state again - no button changes
    let events2 = try parser.parse(data: packet1)
    #expect(!events2.contains(.buttonPressed(.a)))
    #expect(!events2.contains(.buttonReleased(.a)))
  }

}
