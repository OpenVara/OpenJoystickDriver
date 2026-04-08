// DriverKit extension: virtual HID gamepad device (C++ implementation).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The HID report descriptor below matches XboxOneBluetoothHIDDescriptor in
// Sources/OpenJoystickDriverKit/Output/XboxOneBluetoothHIDDescriptor.swift.
//
// We present as 045E:02EA so SDL/PCSX2 auto-map without manual configuration.

#include "OpenJoystickVirtualHIDDevice.h"

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryMap.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOHIDDeviceKeys.h>
#include <HIDDriverKit/IOHIDUsageTables.h>
#include <HIDDriverKit/IOUserHIDDevice.h>
#include <os/log.h>

struct OpenJoystickVirtualHIDDevice_IVars {
    uint64_t setReportCount = 0;
    uint64_t setReportFailCount = 0;
    uint64_t inputReportCount = 0;
    uint64_t lastPublishedSetReportCount = 0;
    uint64_t lastPublishedInputReportCount = 0;
};

// clang-format off

/// HID report descriptor — byte-for-byte copy of XboxOneBluetoothHIDDescriptor.descriptor.
/// Keep both files in sync whenever the descriptor changes.
static const uint8_t HID_REPORT_DESCRIPTOR[] = {
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x01, 0xA1, 0x00, 0x09,
    0x30, 0x09, 0x31, 0x15, 0x00, 0x27, 0xFF, 0xFF, 0x00, 0x00, 0x95, 0x02, 0x75,
    0x10, 0x81, 0x02, 0xC0, 0x09, 0x01, 0xA1, 0x00, 0x09, 0x33, 0x09, 0x34, 0x15,
    0x00, 0x27, 0xFF, 0xFF, 0x00, 0x00, 0x95, 0x02, 0x75, 0x10, 0x81, 0x02, 0xC0,
    0x05, 0x01, 0x09, 0x32, 0x15, 0x00, 0x26, 0xFF, 0x03, 0x95, 0x01, 0x75, 0x0A,
    0x81, 0x02, 0x15, 0x00, 0x25, 0x00, 0x75, 0x06, 0x95, 0x01, 0x81, 0x03, 0x05,
    0x01, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x03, 0x95, 0x01, 0x75, 0x0A, 0x81,
    0x02, 0x15, 0x00, 0x25, 0x00, 0x75, 0x06, 0x95, 0x01, 0x81, 0x03, 0x05, 0x01,
    0x09, 0x39, 0x15, 0x01, 0x25, 0x08, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x66, 0x14,
    0x00, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x75, 0x04, 0x95, 0x01, 0x15, 0x00,
    0x25, 0x00, 0x35, 0x00, 0x45, 0x00, 0x65, 0x00, 0x81, 0x03, 0x05, 0x09, 0x19,
    0x01, 0x29, 0x0A, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0A, 0x81, 0x02,
    0x15, 0x00, 0x25, 0x00, 0x75, 0x06, 0x95, 0x01, 0x81, 0x03, 0x05, 0x01, 0x09,
    0x80, 0x85, 0x02, 0xA1, 0x00, 0x09, 0x85, 0x15, 0x00, 0x25, 0x01, 0x95, 0x01,
    0x75, 0x01, 0x81, 0x02, 0x15, 0x00, 0x25, 0x00, 0x75, 0x07, 0x95, 0x01, 0x81,
    0x03, 0xC0, 0x05, 0x0F, 0x09, 0x21, 0x85, 0x03, 0xA1, 0x02, 0x09, 0x97, 0x15,
    0x00, 0x25, 0x01, 0x75, 0x04, 0x95, 0x01, 0x91, 0x02, 0x15, 0x00, 0x25, 0x00,
    0x75, 0x04, 0x95, 0x01, 0x91, 0x03, 0x09, 0x70, 0x15, 0x00, 0x25, 0x64, 0x75,
    0x08, 0x95, 0x04, 0x91, 0x02, 0x09, 0x50, 0x66, 0x01, 0x10, 0x55, 0x0E, 0x15,
    0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x01, 0x91, 0x02, 0x09, 0xA7, 0x15,
    0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x01, 0x91, 0x02, 0x65, 0x00, 0x55,
    0x00, 0x09, 0x7C, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x01, 0x91,
    0x02, 0xC0, 0x85, 0x04, 0x05, 0x06, 0x09, 0x20, 0x15, 0x00, 0x26, 0xFF, 0x00,
    0x75, 0x08, 0x95, 0x01, 0x81, 0x02, 0xC0,
};

// clang-format on

static constexpr uint32_t HID_REPORT_DESCRIPTOR_SIZE = sizeof(HID_REPORT_DESCRIPTOR);

static inline void publishDebugState(OpenJoystickVirtualHIDDevice* self) {
    auto* ivars = self->ivars;
    if (ivars == nullptr) {
        return;
    }

    // Rate-limit publishing to IORegistry: update every 25 setReport calls, or on any failure.
    const bool shouldPublish =
        (ivars->setReportCount - ivars->lastPublishedSetReportCount) >= 25 ||
        (ivars->inputReportCount - ivars->lastPublishedInputReportCount) >= 25;

    if (!shouldPublish) {
        return;
    }

    auto* dict = OSDictionary::withCapacity(3);
    if (dict == nullptr) {
        return;
    }

    if (auto* n = OSNumber::withNumber(ivars->setReportCount, 64)) {
        OSDictionarySetValue(dict, "SetReportCount", n);
        n->release();
    }
    if (auto* n = OSNumber::withNumber(ivars->setReportFailCount, 64)) {
        OSDictionarySetValue(dict, "SetReportFailCount", n);
        n->release();
    }
    if (auto* n = OSNumber::withNumber(ivars->inputReportCount, 64)) {
        OSDictionarySetValue(dict, "InputReportCount", n);
        n->release();
    }

    // Publish under "DebugState" so user-space can read it via ioreg.
    if (auto* key = OSSymbol::withCString("DebugState")) {
        (void)self->setProperty(key, dict);
        key->release();
    }
    dict->release();

    ivars->lastPublishedSetReportCount = ivars->setReportCount;
    ivars->lastPublishedInputReportCount = ivars->inputReportCount;
}

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

    // Publish an initial debug state snapshot so user-space can reliably read counters
    // even before the first report is sent.
    if (auto* dbg = OSDictionary::withCapacity(3)) {
        if (auto* n = OSNumber::withNumber(static_cast<uint64_t>(0), 64)) {
            OSDictionarySetValue(dbg, "SetReportCount", n);
            n->release();
        }
        if (auto* n = OSNumber::withNumber(static_cast<uint64_t>(0), 64)) {
            OSDictionarySetValue(dbg, "SetReportFailCount", n);
            n->release();
        }
        if (auto* n = OSNumber::withNumber(static_cast<uint64_t>(0), 64)) {
            OSDictionarySetValue(dbg, "InputReportCount", n);
            n->release();
        }
        OSDictionarySetValue(dict, "DebugState", dbg);
        dbg->release();
    }

    // Important:
    // - SDL-based apps may enumerate DriverKit HID devices but not treat them as "real" gamepads.
    // - Our no-reboot Compatibility mode uses a user-space IOHIDUserDevice, which SDL *should*
    //   see as a normal controller.
    //
    // NOTE:
    // We intentionally present the DriverKit device as a "real" controller to SDL-based apps
    // (PCSX2/Steam). This means Transport must NOT be "Virtual" (SDL may filter/penalize it).
    if (auto* transport = OSString::withCString("USB")) {
        OSDictionarySetValue(dict, kIOHIDTransportKey, transport);
        transport->release();
    }
    // Present as an Xbox Wireless Controller so SDL auto-maps it as a "Gamepad".
    // Must match VirtualDeviceProfile.xboxOneS in the Swift layer.
    if (auto* vid = OSNumber::withNumber(static_cast<uint32_t>(0x045E), 32)) {
        OSDictionarySetValue(dict, kIOHIDVendorIDKey, vid);
        vid->release();
    }
    if (auto* pid = OSNumber::withNumber(static_cast<uint32_t>(0x02EA), 32)) {
        OSDictionarySetValue(dict, kIOHIDProductIDKey, pid);
        pid->release();
    }
    // Some consumers treat LocationID=0 as "not a real device". Use a stable non-zero value.
    // Keep this value stable to avoid confusing HID consumers that cache devices by LocationID.
    if (auto* location = OSNumber::withNumber(static_cast<uint32_t>(0x4F4A4401), 32)) {
        OSDictionarySetValue(dict, kIOHIDLocationIDKey, location);
        location->release();
    }
    // Stable (non-hardware) serial number used to disambiguate our virtual device from
    // real controllers that share VID/PID. Safe to expose to user-space.
    if (auto* serial = OSString::withCString("OpenJoystickDriver-DriverKit")) {
        OSDictionarySetValue(dict, kIOHIDSerialNumberKey, serial);
        serial->release();
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
    // SDL's macOS mapping DB expects version=0 for 045E:02EA.
    if (auto* version = OSNumber::withNumber(static_cast<uint32_t>(0x0000), 32)) {
        OSDictionarySetValue(dict, kIOHIDVersionNumberKey, version);
        version->release();
    }
    if (auto* country = OSNumber::withNumber(static_cast<uint32_t>(0), 32)) {
        OSDictionarySetValue(dict, kIOHIDCountryCodeKey, country);
        country->release();
    }

    // Explicitly publish the top-level usage pairs. IOHIDInterface usually derives this
    // from the report descriptor, but providing it here improves compatibility with some
    // user-space enumerators.
    if (auto* pairs = OSArray::withCapacity(1)) {
        if (auto* pair = OSDictionary::withCapacity(2)) {
            if (auto* page =
                    OSNumber::withNumber(static_cast<uint32_t>(kHIDPage_GenericDesktop), 32)) {
                OSDictionarySetValue(pair, kIOHIDDeviceUsagePageKey, page);
                page->release();
            }
            if (auto* u = OSNumber::withNumber(static_cast<uint32_t>(kHIDUsage_GD_GamePad), 32)) {
                OSDictionarySetValue(pair, kIOHIDDeviceUsageKey, u);
                u->release();
            }
            pairs->setObject(pair);
            pair->release();
        }
        OSDictionarySetValue(dict, kIOHIDDeviceUsagePairsKey, pairs);
        pairs->release();
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

    if (ivars != nullptr) {
        ivars->setReportCount += 1;
    }

    // SDL (and some other consumers) will treat repeated setReport failures as a broken device
    // and ignore its input events. Our output path is a daemon → dext relay; we should accept
    // the report, translate it to an input report, and return success even if the relay fails.
    if (report == nullptr) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport called with NULL report");
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    uint64_t len = 0;
    const kern_return_t lenKr = report->GetLength(&len);
    if (lenKr != kIOReturnSuccess || len == 0) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport GetLength failed (kr=%d, len=%llu)",
            static_cast<int>(lenKr),
            len);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    IOBufferMemoryDescriptor* buffer = nullptr;
    const kern_return_t bufKr = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionIn,
        len,
        /* alignment */ 0,
        &buffer);
    if (bufKr != kIOReturnSuccess || buffer == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport failed to allocate buffer (kr=%d, len=%llu)",
            static_cast<int>(bufKr),
            len);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    (void)buffer->SetLength(len);

    IOMemoryMap* reportMap = nullptr;
    IOMemoryMap* bufferMap = nullptr;

    const kern_return_t mapInKr =
        report->CreateMapping(kIOMemoryMapReadOnly, 0, 0, len, 0, &reportMap);
    const kern_return_t mapOutKr = buffer->CreateMapping(0, 0, 0, len, 0, &bufferMap);

    if (mapInKr != kIOReturnSuccess || reportMap == nullptr || mapOutKr != kIOReturnSuccess ||
        bufferMap == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport mapping failed (inKr=%d outKr=%d)",
            static_cast<int>(mapInKr),
            static_cast<int>(mapOutKr));
        if (reportMap != nullptr)
            reportMap->release();
        if (bufferMap != nullptr)
            bufferMap->release();
        buffer->release();
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    void* const src = reinterpret_cast<void*>(static_cast<uintptr_t>(reportMap->GetAddress()));
    void* const dst = reinterpret_cast<void*>(static_cast<uintptr_t>(bufferMap->GetAddress()));
    if (src != nullptr && dst != nullptr) {
        memcpy(dst, src, static_cast<size_t>(len));
    } else {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport map returned NULL address");
        reportMap->release();
        bufferMap->release();
        buffer->release();
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    // Our virtual controller uses Report IDs; the primary gamepad input report is ID 1.
    // We accept output bytes as the payload of report ID 1, then relay them as input.
    const uint32_t reportLen32 = (len > UINT32_MAX) ? UINT32_MAX : static_cast<uint32_t>(len);
    const kern_return_t relayKr =
        handleReport(1, buffer, reportLen32, kIOHIDReportTypeInput, 0);
    if (relayKr != kIOReturnSuccess) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport relay failed (kr=%d, len=%u)",
            static_cast<int>(relayKr),
            reportLen32);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
    } else {
        if (ivars != nullptr) {
            ivars->inputReportCount += 1;
        }
    }

    reportMap->release();
    bufferMap->release();
    buffer->release();
    publishDebugState(this);
    return kIOReturnSuccess;
}
