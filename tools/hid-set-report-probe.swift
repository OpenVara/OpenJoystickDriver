import Foundation
import IOKit
import IOKit.hid

func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
}

func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(device, key as CFString) as? String
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, nil)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("open=0x\(String(openResult, radix: 16))")

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
let targets = devices.filter { device in
  let vendorID = intProp(device, kIOHIDVendorIDKey)
  let serial = strProp(device, kIOHIDSerialNumberKey) ?? ""
  return vendorID == 0x4F4A || vendorID == 0x045E || serial.hasPrefix("OJD-US-")
}
print("targets=\(targets.count)")

for device in targets {
  let vendorID = intProp(device, kIOHIDVendorIDKey)
  let productID = intProp(device, kIOHIDProductIDKey)
  let product = strProp(device, kIOHIDProductKey) ?? "?"
  let report: [UInt8] =
    (vendorID == 0x045E && productID == 0x028E)
    ? [0x00, 0x08, 0x00, 180, 100, 0, 0, 0]
    : [0x4F, 180, 100, 0, 0, 0x2C, 0x01]
  let result = report.withUnsafeBufferPointer { pointer in
    guard let baseAddress = pointer.baseAddress else {
      return kIOReturnBadArgument
    }
    IOHIDDeviceSetReport(
      device,
      kIOHIDReportTypeOutput,
      CFIndex(0),
      baseAddress,
      report.count
    )
  }
  let resultHex = UInt32(bitPattern: result)
  print(
    String(
      format: "%04X:%04X %@ setReport=0x%08x",
      vendorID,
      productID,
      product,
      resultHex
    )
  )
}

IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
