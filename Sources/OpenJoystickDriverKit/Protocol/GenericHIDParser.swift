import Foundation
import SwiftUSB

/// Fallback parser for unrecognized HID game controllers.
/// Uses IOHIDDevice element queries to discover buttons and axes.
public final class GenericHIDParser: InputParser, Sendable {
  private let identifier: DeviceIdentifier

  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    print("[GenericHIDParser] Unrecognized controller " + "\(identifier), using generic mapping")
  }

  // swiftlint:disable async_without_await
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    // TODO: Generic HID requires no handshake; implement protocol conformance.
  }
  // swiftlint:enable async_without_await

  public func parse(data: Data) throws -> [ControllerEvent] { [] }
}
