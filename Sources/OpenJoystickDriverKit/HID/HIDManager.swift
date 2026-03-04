// Sources/OpenJoystickDriverKit/HID/HIDManager.swift

import Foundation
import IOKit.hid

/// Coordinates IOKit HID device discovery for
/// class 0x03 (HID) game controllers.
public final class HIDManager: Sendable {
  private let stream: HIDDeviceStream

  public init() { stream = HIDDeviceStream() }

  /// Returns AsyncStream of HID device events
  /// (connect, disconnect, input).
  public func deviceEvents() -> AsyncStream<HIDDeviceEvent> { stream.deviceEvents() }
}
