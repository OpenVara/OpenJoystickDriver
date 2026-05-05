import Foundation
import SwiftUSB

/// Turns raw bytes from a controller into ``ControllerEvent`` values.
///
/// Each controller protocol (GIP for Xbox, DS4 for PlayStation, GenericHID)
/// has its own implementation. Add a new conforming type when you need to
/// support a new protocol.
public protocol InputParser: AnyObject, Sendable {
  /// Runs the startup handshake the controller needs before it starts sending input.
  ///
  /// For example, GIP controllers require a power-on packet. Protocols that
  /// have no handshake (DS4, GenericHID) leave this as a no-op.
  /// - Parameter handle: The USB device handle. Pass `nil` for HID devices.
  /// - Throws: A protocol-specific error if the handshake fails.
  func performHandshake(handle: USBDeviceHandle?) async throws

  /// Reads one raw data packet and returns zero or more controller events.
  ///
  /// Called once for every USB interrupt transfer or HID input report the
  /// system receives from the controller.
  func parse(data: Data) throws -> [ControllerEvent]

  /// Sends a keep-alive packet so the controller does not power off.
  ///
  /// ``DevicePipeline`` calls this at a regular interval during the input
  /// loop. The default implementation does nothing; override it if the
  /// protocol requires periodic pings (GIP uses CMD 0x03).
  func keepAlive(handle: USBDeviceHandle?) throws
}

extension InputParser {
  /// Default no-op keep-alive implementation.
  public func keepAlive(handle: USBDeviceHandle?) throws {}
}
