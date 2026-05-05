import SwiftUSB

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
