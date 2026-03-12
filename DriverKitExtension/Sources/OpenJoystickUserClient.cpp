// DriverKit extension: user-client that lets the daemon inject HID reports (C++).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The daemon calls IOConnectCallStructMethod(conn, 0, reportBytes, 13, ...)
// to send a 13-byte HID gamepad report.

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSCollections.h>
#include <os/log.h>

#include "OpenJoystickUserClient.h"
#include "OpenJoystickVirtualHIDDevice.h"

static constexpr uint64_t REPORT_SIZE = 13;

struct OpenJoystickUserClient_IVars {
    OpenJoystickVirtualHIDDevice *m_device = nullptr;
};

// Forward declaration of the static dispatch callback.
static kern_return_t static_handle_send_report(OSObject *target, void *reference,
                                               IOUserClientMethodArguments *arguments);

// Dispatch table: selector 0 = send_report (struct input only, 13 bytes).
static const IOUserClientMethodDispatch DISPATCH_TABLE[] = {
    [0] = {
        .function = static_handle_send_report,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = REPORT_SIZE,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
};

static constexpr uint32_t DISPATCH_TABLE_COUNT =
    sizeof(DISPATCH_TABLE) / sizeof(DISPATCH_TABLE[0]);

auto OpenJoystickUserClient::init() -> bool {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(OpenJoystickUserClient_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }
    return true;
}

auto OpenJoystickUserClient::free() -> void {
    OSSafeReleaseNULL(ivars->m_device);
    IOSafeDeleteNULL(ivars, OpenJoystickUserClient_IVars, 1);
    super::free();
}

auto OpenJoystickUserClient::Start_Impl(IOService *provider) -> kern_return_t {
    auto ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ivars->m_device = OSDynamicCast(OpenJoystickVirtualHIDDevice, provider);
    if (ivars->m_device == nullptr) {
        return kIOReturnError;
    }
    ivars->m_device->retain();
    return kIOReturnSuccess;
}

auto OpenJoystickUserClient::Stop_Impl(IOService *provider) -> kern_return_t {
    OSSafeReleaseNULL(ivars->m_device);
    return Stop(provider, SUPERDISPATCH);
}

auto OpenJoystickUserClient::ExternalMethod(
    uint64_t selector,
    IOUserClientMethodArguments *arguments,
    const IOUserClientMethodDispatch *dispatch,
    OSObject *target,
    void *reference) -> kern_return_t {
    if (selector >= DISPATCH_TABLE_COUNT) {
        return kIOReturnUnsupported;
    }
    return super::ExternalMethod(selector, arguments, &DISPATCH_TABLE[selector], this, nullptr);
}

static kern_return_t static_handle_send_report(OSObject *target, void * /* reference */,
                                               IOUserClientMethodArguments *arguments) {
    auto *self = OSDynamicCast(OpenJoystickUserClient, target);
    if (self == nullptr) {
        return kIOReturnBadArgument;
    }

    if (self->ivars->m_device == nullptr) {
        return kIOReturnNotAttached;
    }

    auto *input_data = arguments->structureInput;
    if (input_data == nullptr) {
        return kIOReturnBadArgument;
    }

    // Create a memory descriptor from the incoming data.
    IOBufferMemoryDescriptor *mem = nullptr;
    auto ret = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionInOut, REPORT_SIZE, 0, &mem);
    if (ret != kIOReturnSuccess || mem == nullptr) {
        return kIOReturnNoMemory;
    }

    uint64_t address = 0;
    uint64_t len = 0;
    ret = mem->Map(0, 0, 0, 0, &address, &len);
    if (ret != kIOReturnSuccess) {
        OSSafeReleaseNULL(mem);
        return ret;
    }

    if (len < REPORT_SIZE) {
        OSSafeReleaseNULL(mem);
        return kIOReturnNoMemory;
    }

    memcpy(reinterpret_cast<void *>(address), input_data->getBytesNoCopy(), REPORT_SIZE);

    ret = self->ivars->m_device->send_report(mem, static_cast<uint32_t>(REPORT_SIZE));
    OSSafeReleaseNULL(mem);
    return ret;
}
