// DriverKit extension: virtual HID gamepad device (C++ implementation).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The HID report layout (13 bytes) matches GamepadHIDDescriptor in
// Sources/OpenJoystickDriverKit/Output/GamepadHIDDescriptor.swift.

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOUserHIDDevice.h>
#include <os/log.h>

#include "OpenJoystickVirtualHIDDevice.h"
#include "OpenJoystickUserClient.h"

struct OpenJoystickVirtualHIDDevice_IVars {
    // No instance state needed — the device is stateless once started.
};

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
        // End Collection (Physical)
        0xC0,
    // End Collection (Application)
    0xC0,
};

// clang-format on

static constexpr uint32_t HID_REPORT_DESCRIPTOR_SIZE = sizeof(HID_REPORT_DESCRIPTOR);

bool OpenJoystickVirtualHIDDevice::init() {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(OpenJoystickVirtualHIDDevice_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }
    return true;
}

void OpenJoystickVirtualHIDDevice::free() {
    IOSafeDeleteNULL(ivars, OpenJoystickVirtualHIDDevice_IVars, 1);
    super::free();
}

kern_return_t OpenJoystickVirtualHIDDevice::Start_Impl(IOService *provider) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    RegisterService();
    return kIOReturnSuccess;
}

kern_return_t OpenJoystickVirtualHIDDevice::NewUserClient_Impl(uint32_t type,
                                                                IOUserClient **userClient) {
    IOService *client = nullptr;
    kern_return_t ret = Create(this, "UserClientProperties", &client);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    *userClient = OSDynamicCast(IOUserClient, client);
    if (*userClient == nullptr) {
        client->release();
        return kIOReturnError;
    }
    return kIOReturnSuccess;
}

bool OpenJoystickVirtualHIDDevice::handleStart(IOService *provider) {
    return true;
}

OSDictionary *OpenJoystickVirtualHIDDevice::newDeviceDescription() {
    auto *dict = OSDictionary::withCapacity(8);
    if (dict == nullptr) {
        return nullptr;
    }

    // VID / PID
    auto *vid = OSNumber::withNumber(static_cast<uint64_t>(1), 32);
    auto *pid = OSNumber::withNumber(static_cast<uint64_t>(1), 32);
    dict->setObject("VendorID", vid);
    dict->setObject("ProductID", pid);
    OSSafeReleaseNULL(vid);
    OSSafeReleaseNULL(pid);

    // Product / Manufacturer
    auto *product = OSString::withCString("OpenJoystickDriver Virtual Gamepad");
    auto *manufacturer = OSString::withCString("OpenJoystickDriver");
    dict->setObject("Product", product);
    dict->setObject("Manufacturer", manufacturer);
    OSSafeReleaseNULL(product);
    OSSafeReleaseNULL(manufacturer);

    // Required for GCController / GameController.framework: Generic Desktop / Gamepad
    auto *usage_page = OSNumber::withNumber(static_cast<uint64_t>(1), 32);
    auto *usage = OSNumber::withNumber(static_cast<uint64_t>(5), 32);
    dict->setObject("PrimaryUsagePage", usage_page);
    dict->setObject("PrimaryUsage", usage);
    OSSafeReleaseNULL(usage_page);
    OSSafeReleaseNULL(usage);

    return dict;
}

OSData *OpenJoystickVirtualHIDDevice::newReportDescriptor() {
    return OSData::withBytes(HID_REPORT_DESCRIPTOR, HID_REPORT_DESCRIPTOR_SIZE);
}

kern_return_t OpenJoystickVirtualHIDDevice::send_report(IOMemoryDescriptor *report,
                                                         uint32_t length) {
    return handleReport(0, report, length, kIOHIDReportTypeInput, 0);
}
