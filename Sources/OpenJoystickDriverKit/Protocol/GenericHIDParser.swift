import Foundation
import SwiftUSB
import os

public final class GenericHIDParser: InputParser, Sendable {
  private let identifier: DeviceIdentifier
  private let didLogParseWarning = OSAllocatedUnfairLock(initialState: false)

  public init(identifier: DeviceIdentifier) {
    self.identifier = identifier
    print("[GenericHIDParser] Unrecognized controller \(identifier), using generic mapping")
  }

  // swiftlint:disable async_without_await
  public func performHandshake(handle: USBDeviceHandle?) async throws {}
  // swiftlint:enable async_without_await

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
