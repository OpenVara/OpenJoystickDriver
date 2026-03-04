import Foundation
import IOKit.hid

/// An event from the IOKit HID subsystem for a class-0x03 controller.
///
/// ``HIDManager`` sends these to ``DeviceManager`` to report when a
/// HID controller is plugged in, unplugged, or sends an input report.
public enum HIDDeviceEvent: Sendable {
  /// A HID controller was plugged in. Carries its USB identifiers and name.
  case connected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?
  )
  /// A previously connected HID controller was unplugged.
  case disconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
  /// The controller sent a raw input report (button presses, stick positions, etc.).
  case inputReport(locationID: UInt32, data: Data)
}
