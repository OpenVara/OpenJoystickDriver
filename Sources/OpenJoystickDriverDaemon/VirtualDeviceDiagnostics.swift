import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

enum VirtualDeviceDiagnostics {
  private static let ioUserClassKey = "IOUserClass"

  static func enumerateHIDGamepads() -> [XPCHIDGamepadSnapshot] {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // Do broad matching and filter in-process. Some dext versions may not match
    // correctly under the GamePad usage filter during extension replacement/upgrade.
    IOHIDManagerSetDeviceMatching(mgr, nil)

    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      // Still attempt CopyDevices; some systems return warnings here.
      print("[VirtualDeviceDiagnostics] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
    }

    let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
    func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
      let primaryPage = intProp(device, kIOHIDPrimaryUsagePageKey)
      let primaryUsage = intProp(device, kIOHIDPrimaryUsageKey)
      if primaryPage == kHIDPage_GenericDesktop && primaryUsage == kHIDUsage_GD_GamePad {
        return true
      }
      if let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[
        String: Any
      ]] {
        for pair in pairs {
          let page = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
          let usage = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
          if page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad { return true }
        }
      }
      return false
    }

    let snapshots: [XPCHIDGamepadSnapshot] = devices.compactMap { device in
      let vid = intProp(device, kIOHIDVendorIDKey)
      let pid = intProp(device, kIOHIDProductIDKey)
      let product = strProp(device, kIOHIDProductKey)
      let transport = strProp(device, kIOHIDTransportKey)
      let location = intProp(device, kIOHIDLocationIDKey)
      let serial = strProp(device, kIOHIDSerialNumberKey)
      let ioUserClass = IOHIDDeviceGetProperty(device, ioUserClassKey as CFString) as? String

      let isOJDDriverKit = (ioUserClass == "OpenJoystickVirtualHIDDevice")
      let isOJDUserSpace =
        (ioUserClass == "IOHIDUserDevice")
        || (serial == UserSpaceVirtualDeviceConstants.serialNumber)

      // Only report:
      // - OJD virtual devices (DriverKit or user-space), OR
      // - real devices that look like GamePads (keeps the list relevant).
      if !isOJDDriverKit && !isOJDUserSpace && !looksLikeGamepad(device) {
        return nil
      }

      let serialKind: XPCSerialKind =
        (serial == nil || serial == "") ? .none
        : ((serial == UserSpaceVirtualDeviceConstants.serialNumber) ? .ojdUserSpace : .present)

      return XPCHIDGamepadSnapshot(
        vendorID: UInt16(truncatingIfNeeded: vid),
        productID: UInt16(truncatingIfNeeded: pid),
        product: product,
        transport: transport,
        locationID: location == 0 ? nil : UInt32(truncatingIfNeeded: location),
        serialKind: serialKind,
        ioUserClass: ioUserClass,
        isOJDDriverKit: isOJDDriverKit,
        isOJDUserSpace: isOJDUserSpace
      )
    }.sorted { a, b in
      if a.isOJDDriverKit != b.isOJDDriverKit { return a.isOJDDriverKit && !b.isOJDDriverKit }
      if a.isOJDUserSpace != b.isOJDUserSpace { return a.isOJDUserSpace && !b.isOJDUserSpace }
      if a.vendorID != b.vendorID { return a.vendorID < b.vendorID }
      return a.productID < b.productID
    }

    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    return snapshots
  }

  private static func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  private static func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }
}
