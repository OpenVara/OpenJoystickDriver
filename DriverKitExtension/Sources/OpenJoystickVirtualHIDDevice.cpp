// DriverKit extension: virtual HID gamepad device (C++ implementation).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The HID report layout (15 bytes) matches GamepadHIDDescriptor in
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

#include "gamepad_hid_descriptor.h"

struct OpenJoystickVirtualHIDDevice_IVars {};

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
    // Xbox One S VID/PID — enables auto-detection by SDL3, GCController, and browsers.
    // VID/PID must match VirtualDeviceProfile.xboxOneS in the Swift layer.
    // The dext identity is immutable at runtime — all protocols normalize
    // to this profile via ControllerEvent → XInputHID report.
    if (auto* vid = OSNumber::withNumber(static_cast<uint32_t>(0x045E), 32)) {
        OSDictionarySetValue(dict, kIOHIDVendorIDKey, vid);
        vid->release();
    }
    if (auto* pid = OSNumber::withNumber(static_cast<uint32_t>(0x02EA), 32)) {
        OSDictionarySetValue(dict, kIOHIDProductIDKey, pid);
        pid->release();
    }
    if (auto* location = OSNumber::withNumber(static_cast<uint32_t>(0), 32)) {
        OSDictionarySetValue(dict, kIOHIDLocationIDKey, location);
        location->release();
    }
    if (auto* product = OSString::withCString("Xbox Wireless Controller")) {
        OSDictionarySetValue(dict, kIOHIDProductKey, product);
        product->release();
    }
    if (auto* manufacturer = OSString::withCString("Microsoft")) {
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
    if (auto* version = OSNumber::withNumber(static_cast<uint32_t>(0x0408), 32)) {
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
        GAMEPAD_HID_REPORT_DESCRIPTOR_SIZE);
    auto* data =
        OSData::withBytes(GAMEPAD_HID_REPORT_DESCRIPTOR, GAMEPAD_HID_REPORT_DESCRIPTOR_SIZE);
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
