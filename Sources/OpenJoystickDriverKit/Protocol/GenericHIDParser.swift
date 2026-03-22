import Foundation
import SwiftUSB
import os

/// Fallback parser for unrecognized HID game controllers.
///
/// Uses IOHIDDevice element queries to discover buttons and axes.
public final class GenericHIDParser: InputParser, Sendable {
  private let identifier: DeviceIdentifier
  private let didLogParseWarning = OSAllocatedUnfairLock(initialState: false)

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
    didLogParseWarning.withLock { warned in
      if !warned {
        print(
          "[GenericHIDParser] Dropping input from \(identifier)"
            + " — no parser implemented for this controller"
        )
        warned = true
      }
    }
    return []
  }
}
