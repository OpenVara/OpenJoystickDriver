// DriverKit C++20 interop header.
//
// Include this from Swift via a bridging header or via C++ interop mode
// (SWIFT_OBJC_INTEROP_MODE = objcxx in project.yml).
//
// DriverKit C++ API lives in <DriverKit/DriverKit.h> and
// <HIDDriverKit/HIDDriverKit.h>. Import them here for shared utilities
// that are either missing from the Swift overlay or need zero-overhead
// inline implementations.
//
// Key constraints:
//   - C++ exceptions are DISABLED (GCC_ENABLE_CPP_EXCEPTIONS=NO).
//   - RTTI is DISABLED (GCC_ENABLE_CPP_RTTI=NO).
//   - Use __attribute__((swift_name("..."))) to expose C++ functions to Swift.

#pragma once
#include <DriverKit/DriverKit.h>
#include <HIDDriverKit/HIDDriverKit.h>
