import Foundation
import IOKit.hid

/// Manages discovery of USB class 0x03 (HID) game controllers via IOKit.
///
/// This is the entry point for HID-class devices (for example, DualShock 4).
/// It wraps `HIDDeviceStream` and exposes a single async stream of device
/// events. USB class 0xFF (vendor-specific) devices use SwiftUSB instead.
public final class HIDManager: Sendable {
  private let stream: HIDDeviceStream

  public init() { stream = HIDDeviceStream() }

  /// Returns a live stream of HID device events (connect, disconnect, input report).
  public func deviceEvents() -> AsyncStream<HIDDeviceEvent> { stream.deviceEvents() }
}
