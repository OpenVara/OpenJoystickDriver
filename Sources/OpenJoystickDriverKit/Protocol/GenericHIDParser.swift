import Foundation
import SwiftUSB

/// Fallback parser for unrecognized HID game controllers.
///
/// Uses IOHIDDevice element queries to discover buttons and axes.
public final class GenericHIDParser: InputParser, Sendable {
  private let identifier: DeviceIdentifier

  /// Creates a new GenericHIDParser for the given device identifier.
  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    print("[GenericHIDParser] Unrecognized controller " + "\(identifier), using generic mapping")
  }

  // swiftlint:disable async_without_await
  /// No-op; generic HID controllers require no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    // No handshake required for generic HID controllers.
  }
  // swiftlint:enable async_without_await

  /// Returns an empty event list; generic HID input parsing is not yet implemented.
  public func parse(data: Data) throws -> [ControllerEvent] { [] }
}
