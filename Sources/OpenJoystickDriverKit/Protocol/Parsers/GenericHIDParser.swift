import Foundation
import SwiftUSB

/// Fallback parser for unrecognized HID game controllers.
///
/// Uses IOHIDDevice element queries to discover buttons and axes.
public final class GenericHIDParser: InputParser, @unchecked Sendable {
  private let identifier: DeviceIdentifier
  private let warningLock = NSLock()
  private var didLogParseWarning = false

  /// Creates a new GenericHIDParser for the given device identifier.
  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    print("[GenericHIDParser] Unrecognized controller \(identifier), using generic mapping")
  }

  // swiftlint:disable async_without_await
  /// No-op; generic HID controllers require no handshake.
  public func performHandshake(handle: USBDeviceHandle?) async throws {}
  // swiftlint:enable async_without_await

  /// Returns an empty event list; generic HID input parsing is not yet implemented.
  public func parse(data: Data) throws -> [ControllerEvent] {
    warningLock.lock()
    defer { warningLock.unlock() }
    if !didLogParseWarning {
      print(
        "[GenericHIDParser] Dropping input from \(identifier)"
          + " — no parser implemented for this controller"
      )
      didLogParseWarning = true
    }
    return []
  }
}
