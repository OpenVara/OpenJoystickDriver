// Sources/OpenJoystickDriverKit/HID/HIDDeviceEvent.swift

import Foundation
import IOKit.hid

public enum HIDDeviceEvent: Sendable {
  case connected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?
  )
  case disconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
  case inputReport(locationID: UInt32, data: Data)
}
