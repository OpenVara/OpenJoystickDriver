import SwiftUSB

/// A raw HID output report that can be sent through IOKit.
public struct PhysicalHIDOutputReport: Equatable, Sendable {
  public let reportID: UInt8
  public let bytes: [UInt8]

  public init(reportID: UInt8, bytes: [UInt8]) {
    self.reportID = reportID
    self.bytes = bytes
  }
}

/// Optional physical output support exposed by USB-backed controller protocols.
public protocol PhysicalRumbleOutput: AnyObject, Sendable {
  /// True when the protocol has source-backed physical rumble output.
  var supportsPhysicalRumble: Bool { get }

  /// Sends physical rumble to the source controller.
  ///
  /// Values are 0...255. Protocols without trigger motors may ignore `lt` and `rt`.
  func sendPhysicalRumble(
    handle: USBDeviceHandle,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8
  ) throws
}

extension PhysicalRumbleOutput {
  public var supportsPhysicalRumble: Bool { true }
}

/// Optional physical output support exposed by HID-backed controller protocols.
public protocol PhysicalHIDRumbleOutput: AnyObject, Sendable {
  var supportsPhysicalRumble: Bool { get }

  func physicalRumbleReport(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8)
    -> PhysicalHIDOutputReport
}

extension PhysicalHIDRumbleOutput {
  public var supportsPhysicalRumble: Bool { true }
}
