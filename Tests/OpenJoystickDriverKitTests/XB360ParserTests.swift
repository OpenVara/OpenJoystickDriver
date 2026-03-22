import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("XB360 Parser Tests") struct XB360ParserTests {

  private func makePacket(
    buttons0: UInt8 = 0,
    buttons1: UInt8 = 0,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    leftStickX: Int16 = 0,
    leftStickY: Int16 = 0,
    rightStickX: Int16 = 0,
    rightStickY: Int16 = 0
  ) -> Data {
    var data = Data(repeating: 0, count: 20)
    data[0] = 0x00  // message type: input
    data[1] = 0x14  // length
    data[2] = buttons0
    data[3] = buttons1
    data[4] = leftTrigger
    data[5] = rightTrigger
    let lsx = leftStickX.littleEndian
    data[6] = UInt8(lsx & 0xFF)
    data[7] = UInt8((lsx >> 8) & 0xFF)
    let lsy = leftStickY.littleEndian
    data[8] = UInt8(lsy & 0xFF)
    data[9] = UInt8((lsy >> 8) & 0xFF)
    let rsx = rightStickX.littleEndian
    data[10] = UInt8(rsx & 0xFF)
    data[11] = UInt8((rsx >> 8) & 0xFF)
    let rsy = rightStickY.littleEndian
    data[12] = UInt8(rsy & 0xFF)
    data[13] = UInt8((rsy >> 8) & 0xFF)
    return data
  }

  @Test func shortPacketReturnsEmpty() throws {
    let parser = XB360Parser()
    let events = try parser.parse(data: Data([0x00, 0x14, 0x00]))
    #expect(events.isEmpty)
  }

  @Test func nonInputMessageTypeReturnsEmpty() throws {
    let parser = XB360Parser()
    var data = makePacket()
    data[0] = 0x01
    let events = try parser.parse(data: data)
    #expect(events.isEmpty)
  }

  @Test func allZeroFirstPacketEmitsNoStickEvents() throws {
    let parser = XB360Parser()
    let events = try parser.parse(data: makePacket())
    let hasStick = events.contains {
      if case .leftStickChanged = $0 { return true }
      if case .rightStickChanged = $0 { return true }
      return false
    }
    #expect(!hasStick)
  }

  @Test func aButtonPress() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons1: 0x10))
    #expect(events.contains(.buttonPressed(.a)))
  }

  @Test func aButtonRelease() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket(buttons1: 0x10))
    let events = try parser.parse(data: makePacket(buttons1: 0x00))
    #expect(events.contains(.buttonReleased(.a)))
  }

  @Test func allFaceButtons() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons1: 0x10 | 0x20 | 0x40 | 0x80))
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.x)))
    #expect(events.contains(.buttonPressed(.y)))
  }

  @Test func bumperAndGuide() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons1: 0x01 | 0x02 | 0x04))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.buttonPressed(.rightBumper)))
    #expect(events.contains(.buttonPressed(.guide)))
  }

  @Test func startBackStickClicks() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons0: 0x10 | 0x20 | 0x40 | 0x80))
    #expect(events.contains(.buttonPressed(.start)))
    #expect(events.contains(.buttonPressed(.back)))
    #expect(events.contains(.buttonPressed(.leftStick)))
    #expect(events.contains(.buttonPressed(.rightStick)))
  }

  @Test func dpadNorth() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons0: 0x01))
    #expect(events.contains(.dpadChanged(.north)))
  }

  @Test func dpadDiagonal() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(buttons0: 0x09))
    #expect(events.contains(.dpadChanged(.northEast)))
  }

  @Test func leftTrigger() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(leftTrigger: 255))
    let hasTrigger = events.contains {
      if case .leftTriggerChanged(let v) = $0 { return abs(v - 1.0) < 0.01 }
      return false
    }
    #expect(hasTrigger)
  }

  @Test func rightTrigger() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(rightTrigger: 128))
    let hasTrigger = events.contains {
      if case .rightTriggerChanged(let v) = $0 { return abs(v - 128.0 / 255.0) < 0.01 }
      return false
    }
    #expect(hasTrigger)
  }

  @Test func leftStickFullDeflection() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket())
    let events = try parser.parse(data: makePacket(leftStickX: 32767, leftStickY: -32767))
    let hasStick = events.contains {
      if case .leftStickChanged(let x, let y) = $0 {
        return abs(x - 1.0) < 0.01 && abs(y - 1.0) < 0.01
      }
      return false
    }
    #expect(hasStick)
  }

  @Test func unchangedInputEmitsNoEvents() throws {
    let parser = XB360Parser()
    _ = try parser.parse(data: makePacket(buttons1: 0x10))
    let events = try parser.parse(data: makePacket(buttons1: 0x10))
    #expect(events.isEmpty)
  }
}
