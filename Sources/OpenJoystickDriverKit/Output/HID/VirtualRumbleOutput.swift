import Foundation
import IOKit.hid

public struct VirtualRumbleCommand: Equatable, Sendable {
  public let left: UInt8
  public let right: UInt8
  public let leftTrigger: UInt8
  public let rightTrigger: UInt8
  public let durationMs: Int

  public init(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    durationMs: Int = 250
  ) {
    self.left = left
    self.right = right
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.durationMs = durationMs
  }
}

public enum VirtualRumbleOutputReportParser {
  public static func parse(
    type: IOHIDReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> VirtualRumbleCommand? {
    guard type == kIOHIDReportTypeOutput || type == kIOHIDReportTypeFeature else { return nil }

    if let command = parseXboxOneReport(reportID: reportID, bytes: bytes) {
      return command
    }
    if let command = parseXbox360Report(reportID: reportID, bytes: bytes) {
      return command
    }
    if let command = parseOJDReport(reportID: reportID, bytes: bytes) {
      return command
    }
    return nil
  }

  private static func parseXboxOneReport(
    reportID: UInt32,
    bytes: [UInt8]
  ) -> VirtualRumbleCommand? {
    let payload: [UInt8]
    if reportID == 3 {
      payload = bytes
    } else if reportID == 0, bytes.first == 0x03 {
      payload = Array(bytes.dropFirst())
    } else {
      return nil
    }
    guard payload.count >= 5 else { return nil }
    let activation = payload[0] & 0x0F
    let leftTrigger = (activation & 0x01) != 0 ? payload[1] : 0
    let rightTrigger = (activation & 0x02) != 0 ? payload[2] : 0
    let left = (activation & 0x04) != 0 ? payload[3] : 0
    let right = (activation & 0x08) != 0 ? payload[4] : 0
    let duration = payload.count >= 6 ? Int(payload[5]) * 10 : 250
    return VirtualRumbleCommand(
      left: left,
      right: right,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger,
      durationMs: max(0, duration)
    )
  }

  private static func parseXbox360Report(
    reportID: UInt32,
    bytes: [UInt8]
  ) -> VirtualRumbleCommand? {
    let payload: [UInt8]
    if reportID == 0 {
      payload = bytes
    } else {
      return nil
    }

    if payload.count >= 8, payload[0] == 0x00, payload[1] == 0x08 {
      return VirtualRumbleCommand(left: payload[3], right: payload[4])
    }
    if payload.count >= 4, payload[0] == 0x08 {
      return VirtualRumbleCommand(left: payload[2], right: payload[3])
    }
    return nil
  }

  private static func parseOJDReport(reportID: UInt32, bytes: [UInt8]) -> VirtualRumbleCommand? {
    guard reportID == 0 else { return nil }
    let payload: [UInt8]
    if bytes.first == 0x4F {
      payload = Array(bytes.dropFirst())
    } else {
      payload = bytes
    }
    guard payload.count >= 4 else { return nil }
    let duration: Int
    if payload.count >= 6 {
      duration = Int(UInt16(payload[4]) | (UInt16(payload[5]) << 8))
    } else {
      duration = 250
    }
    return VirtualRumbleCommand(
      left: payload[0],
      right: payload[1],
      leftTrigger: payload[2],
      rightTrigger: payload[3],
      durationMs: duration
    )
  }
}
