// DriverKit extension: virtual HID gamepad device (C++ implementation).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The HID report layout (13 bytes) matches GamepadHIDDescriptor in
// Sources/OpenJoystickDriverKit/Output/GamepadHIDDescriptor.swift.

#include "OpenJoystickVirtualHIDDevice.h"

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOHIDDeviceKeys.h>
#include <HIDDriverKit/IOHIDUsageTables.h>
#include <HIDDriverKit/IOUserHIDDevice.h>
#include <os/log.h>

struct OpenJoystickVirtualHIDDevice_IVars {};

// clang-format off

/// HID report descriptor — byte-for-byte copy of GamepadHIDDescriptor.descriptor.
/// Keep both files in sync whenever the descriptor changes.
static const uint8_t HID_REPORT_DESCRIPTOR[] = {
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
            // 13-byte output report (daemon → dext relay)
            0x09, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00,
            0x75, 0x08, 0x95, 0x0D, 0x91, 0x02,
        // End Collection (Physical)
        0xC0,
    // End Collection (Application)
    0xC0,
};

// clang-format on

static constexpr uint32_t HID_REPORT_DESCRIPTOR_SIZE = sizeof(HID_REPORT_DESCRIPTOR);

auto OpenJoystickVirtualHIDDevice::init() -> bool {
    if (!super::init())
        return false;
    ivars = IONewZero(OpenJoystickVirtualHIDDevice_IVars, 1);
    if (ivars == nullptr) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: failed to allocate ivars");
        return false;
    }
    return true;
}

auto OpenJoystickVirtualHIDDevice::free() -> void {
    IOSafeDeleteNULL(ivars, OpenJoystickVirtualHIDDevice_IVars, 1);
    super::free();
}

auto OpenJoystickVirtualHIDDevice::handleStart(IOService* provider) -> bool {
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: handleStart ENTRY");
    if (!super::handleStart(provider)) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: super::handleStart failed");
        return false;
    }
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: handleStart succeeded");
    return true;
}

auto OpenJoystickVirtualHIDDevice::newDeviceDescription() -> OSDictionary* {
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: newDeviceDescription called");

    auto* dict = OSDictionary::withCapacity(12);
    if (dict == nullptr) {
        return nullptr;
    }

    // Tell IOHIDDevice::start to call registerService on our behalf.
    OSDictionarySetValue(dict, "RegisterService", kOSBooleanTrue);
    OSDictionarySetValue(dict, "HIDDefaultBehavior", kOSBooleanTrue);

    if (auto* transport = OSString::withCString("Virtual")) {
        OSDictionarySetValue(dict, kIOHIDTransportKey, transport);
        transport->release();
    }
    if (auto* vid = OSNumber::withNumber(static_cast<uint32_t>(0x1234), 32)) {
        OSDictionarySetValue(dict, kIOHIDVendorIDKey, vid);
        vid->release();
    }
    if (auto* pid = OSNumber::withNumber(static_cast<uint32_t>(0x0001), 32)) {
        OSDictionarySetValue(dict, kIOHIDProductIDKey, pid);
        pid->release();
    }
    if (auto* location = OSNumber::withNumber(static_cast<uint32_t>(0), 32)) {
        OSDictionarySetValue(dict, kIOHIDLocationIDKey, location);
        location->release();
    }
    if (auto* product = OSString::withCString("OpenJoystickDriver Virtual Gamepad")) {
        OSDictionarySetValue(dict, kIOHIDProductKey, product);
        product->release();
    }
    if (auto* manufacturer = OSString::withCString("OpenJoystickDriver")) {
        OSDictionarySetValue(dict, kIOHIDManufacturerKey, manufacturer);
        manufacturer->release();
    }
    if (auto* usage_page =
            OSNumber::withNumber(static_cast<uint32_t>(kHIDPage_GenericDesktop), 32)) {
        OSDictionarySetValue(dict, kIOHIDPrimaryUsagePageKey, usage_page);
        usage_page->release();
    }
    if (auto* usage = OSNumber::withNumber(static_cast<uint32_t>(kHIDUsage_GD_GamePad), 32)) {
        OSDictionarySetValue(dict, kIOHIDPrimaryUsageKey, usage);
        usage->release();
    }
    if (auto* version = OSNumber::withNumber(static_cast<uint32_t>(0x0100), 32)) {
        OSDictionarySetValue(dict, kIOHIDVersionNumberKey, version);
        version->release();
    }
    if (auto* country = OSNumber::withNumber(static_cast<uint32_t>(0), 32)) {
        OSDictionarySetValue(dict, kIOHIDCountryCodeKey, country);
        country->release();
    }

    return dict;
}

auto OpenJoystickVirtualHIDDevice::newReportDescriptor() -> OSData* {
    os_log(
        OS_LOG_DEFAULT,
        "OpenJoystickVirtualHID: newReportDescriptor called, size=%u",
        HID_REPORT_DESCRIPTOR_SIZE);
    auto* data = OSData::withBytes(HID_REPORT_DESCRIPTOR, HID_REPORT_DESCRIPTOR_SIZE);
    if (data == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: newReportDescriptor — OSData::withBytes returned NULL");
    }
    return data;
}

auto OpenJoystickVirtualHIDDevice::setReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits /* options */,
    uint32_t /* completionTimeout */,
    OSAction* /* action */) -> kern_return_t {
    if (reportType != kIOHIDReportTypeOutput)
        return kIOReturnUnsupported;
    uint64_t len = 0;
    report->GetLength(&len);
    return handleReport(0, report, static_cast<uint32_t>(len), kIOHIDReportTypeInput, 0);
}
