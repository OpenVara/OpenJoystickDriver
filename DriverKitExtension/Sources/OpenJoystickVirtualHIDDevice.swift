// DriverKit extension: virtual HID gamepad device.
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit), NOT the macOS SDK.
// Swift concurrency strict mode is intentionally disabled (project.yml) — DriverKit
// predates Swift concurrency and the overlay types are not Sendable.
//
// IMPORTANT: Verify the exact Swift overlay signatures for `handleReport`,
// `newDeviceDescription`, and `newUserClient` against your installed Xcode /
// DriverKit SDK. Apple revises these APIs between Xcode major versions.
// The signatures below target DriverKit 23.0 (Xcode 15 / macOS 13).

import DriverKit
import HIDDriverKit

/// IOUserHIDDevice subclass that presents itself to the system as a generic
/// USB HID gamepad. The device node is published into IORegistry via
/// `RegisterService()` and remains alive for the lifetime of the extension.
///
/// Reports are injected by the daemon via ``OpenJoystickUserClient`` using
/// IOKit `IOConnectCallStructMethod` — no `hid.virtual.device` entitlement is
/// required on the daemon side.
///
/// The HID report layout (13 bytes) is identical to `GamepadHIDDescriptor`
/// in `Sources/OpenJoystickDriverKit/Output/GamepadHIDDescriptor.swift`.
/// Keep both in sync whenever the descriptor changes.
class OpenJoystickVirtualHIDDevice: IOUserHIDDevice {

  // MARK: - Lifecycle

  override func Start(_ provider: IOService?) -> IOReturn {
    let ret = super.Start(provider)
    guard ret == kIOReturnSuccess else { return ret }
    // Publish the device node so the HID system and GCController discover it.
    RegisterService()
    return kIOReturnSuccess
  }

  // MARK: - Device description

  /// Returns the property dictionary that describes this virtual HID device.
  /// HIDDriverKit uses this to configure the IOHIDDevice node in the registry.
  override func newDeviceDescription() -> OSDictionary? {
    guard let dict = OSDictionary(capacity: 8) else { return nil }

    // --- HID descriptor ---
    // Byte-for-byte copy of GamepadHIDDescriptor.descriptor.
    // (Sources/OpenJoystickDriverKit/Output/GamepadHIDDescriptor.swift)
    // Update both files if the report layout changes.
    let descriptorBytes: [UInt8] = [
      // Usage Page: Generic Desktop
      0x05, 0x01,
      // Usage: Gamepad
      0x09, 0x05,
      // Collection: Application
      0xA1, 0x01,
        // Collection: Physical
        0xA1, 0x00,
          // 16 digital buttons (Button page, usages 1–16)
          0x05, 0x09, 0x19, 0x01, 0x29, 0x10, 0x15, 0x00,
          0x25, 0x01, 0x75, 0x01, 0x95, 0x10, 0x81, 0x02,
          // 4 × 16-bit axes (LSX, LSY, RSX, RSY)
          0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x33,
          0x09, 0x34, 0x16, 0x01, 0x80, 0x26, 0xFF, 0x7F,
          0x75, 0x10, 0x95, 0x04, 0x81, 0x02,
          // 2 × 8-bit triggers (Z = LT, Rz = RT)
          0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF,
          0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
          // Hat switch (D-pad, 4-bit nibble, Null State)
          0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00,
          0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95,
          0x01, 0x81, 0x42,
          // 4-bit pad to byte-align the hat nibble
          0x75, 0x04, 0x95, 0x01, 0x81, 0x03,
        // End Collection (Physical)
        0xC0,
      // End Collection (Application)
      0xC0,
    ]

    // NOTE: OSData(bytes:count:) signature — verify against your DriverKit SDK.
    if let data = OSData(bytes: descriptorBytes, count: descriptorBytes.count) {
      dict.setObject(data, forKey: "HIDDescriptor" as NSString)
    }

    // NOTE: OSNumber(value:) with UInt64 — verify against your DriverKit SDK.
    dict.setObject(OSNumber(value: UInt64(1)), forKey: "VendorID" as NSString)
    dict.setObject(OSNumber(value: UInt64(1)), forKey: "ProductID" as NSString)
    // NOTE: OSString(cString:) / OSString(string:) — verify against DriverKit SDK.
    dict.setObject(
      OSString(cString: "OpenJoystickDriver Virtual Gamepad"),
      forKey: "Product" as NSString
    )
    dict.setObject(
      OSString(cString: "OpenJoystickDriver"),
      forKey: "Manufacturer" as NSString
    )
    // Required for GCController / GameController.framework: Generic Desktop / Gamepad
    dict.setObject(OSNumber(value: UInt64(1)), forKey: "PrimaryUsagePage" as NSString)
    dict.setObject(OSNumber(value: UInt64(5)), forKey: "PrimaryUsage" as NSString)

    return dict
  }

  // MARK: - Report injection

  /// Injects a 13-byte HID input report into the system HID stack.
  /// Called by ``OpenJoystickUserClient`` when the daemon sends a new gamepad state.
  ///
  /// - Parameters:
  ///   - report: Memory descriptor whose contents are the 13-byte HID report.
  ///   - length: Must equal 13 (``GamepadHIDDescriptor.reportSize``).
  /// - Returns: `kIOReturnSuccess` on success; IOKit error otherwise.
  func sendReport(_ report: IOMemoryDescriptor, length: UInt32) -> IOReturn {
    // NOTE: Verify the exact `handleReport` signature for your DriverKit SDK:
    //   func handleReport(_ report: IOMemoryDescriptor,
    //                     withLength: UInt32, andTimestamp: UInt64,
    //                     andType: IOHIDReportType, andOptions: IOOptionBits) -> IOReturn
    // Passing timestamp 0 lets the kernel timestamp the event.
    return handleReport(
      report,
      withLength: length,
      andTimestamp: 0,
      andType: kIOHIDReportTypeInput,
      andOptions: 0
    )
  }

  // MARK: - User client

  /// Allocates an ``OpenJoystickUserClient`` for each connecting client (the daemon).
  ///
  /// - Note: Verify exact `newUserClient` signature for DriverKit 23.x:
  ///   The second parameter type may be `UnsafeMutablePointer<Unmanaged<IOUserClient>?>?`
  ///   or use `IOUserClient2022` depending on your SDK version.
  override func newUserClient(
    _ type: UInt32,
    userClient: AutoreleasingUnsafeMutablePointer<IOUserClient2022?>?
  ) -> IOReturn {
    let client = OpenJoystickUserClient()
    client.device = self
    userClient?.pointee = client
    return kIOReturnSuccess
  }

  // MARK: - Required stubs

  // IOUserHIDDevice requires get/setReport overrides; we only support injection
  // via handleReport (user-client path), not host-initiated get/set.

  override func getReport(
    _ report: IOMemoryDescriptor?,
    reportType: IOHIDReportType,
    options: IOOptionBits,
    completion: IOUserHIDRequestReportCompletion
  ) {
    completion(kIOReturnUnsupported, 0)
  }

  override func setReport(
    _ report: IOMemoryDescriptor?,
    reportType: IOHIDReportType,
    options: IOOptionBits,
    completion: IOUserHIDRequestReportCompletion
  ) {
    completion(kIOReturnUnsupported, 0)
  }
}
