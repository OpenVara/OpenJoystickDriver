// DriverKit extension: user-client that lets the daemon inject HID reports.
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit), NOT the macOS SDK.
//
// IMPORTANT: Verify IOUserClient2022 / externalMethod signatures and
// IOUserClientMethodArguments field names against your installed DriverKit SDK.
// Apple revises these between Xcode major versions.
// The signatures below target DriverKit 23.0 (Xcode 15 / macOS 13).

import DriverKit

/// IOKit user-client that allows the daemon to inject 13-byte HID gamepad
/// reports into the virtual device via `IOConnectCallStructMethod(conn, 0, ...)`.
///
/// ## Wire protocol
/// - Selector **0** (`sendReport`): `structureInput` must be exactly 13 bytes
///   matching the layout of ``GamepadReport`` / `GamepadHIDDescriptor.reportSize`.
class OpenJoystickUserClient: IOUserClient2022 {

  /// Weak reference to the owning HID device; set by
  /// ``OpenJoystickVirtualHIDDevice/newUserClient(_:userClient:)``.
  var device: OpenJoystickVirtualHIDDevice?

  // MARK: - Selectors

  enum UserClientSelector: UInt32 {
    /// Send one 13-byte HID input report to the virtual gamepad.
    case sendReport = 0
  }

  // MARK: - Report layout
  //
  // Mirror of GamepadHIDDescriptor report layout
  // (Sources/OpenJoystickDriverKit/Output/GamepadHIDDescriptor.swift):
  //   bytes 0–1  : button bitmask (UInt16 LE)
  //   bytes 2–3  : left  stick X  (Int16 LE)
  //   bytes 4–5  : left  stick Y  (Int16 LE)
  //   bytes 6–7  : right stick X  (Int16 LE)
  //   bytes 8–9  : right stick Y  (Int16 LE)
  //   byte  10   : left  trigger  (UInt8)
  //   byte  11   : right trigger  (UInt8)
  //   byte  12   : hat switch     (low nibble)
  static let reportSize: UInt64 = 13

  // MARK: - External method dispatch

  /// Dispatches incoming IOConnectCallStructMethod calls from the daemon.
  ///
  /// - Note: `completion` is non-nil only for async methods; our `sendReport`
  ///   method is synchronous so we ignore it.
  override func externalMethod(
    _ selector: UInt32,
    arguments: IOUserClientMethodArguments,
    completion: IOUserClientMethodCompletion?
  ) -> IOReturn {
    switch UserClientSelector(rawValue: selector) {
    case .sendReport:
      return handleSendReport(arguments: arguments)
    case nil:
      return kIOReturnUnsupported
    }
  }

  // MARK: - clientClose

  override func clientClose() -> IOReturn {
    device = nil
    return super.clientClose()
  }

  // MARK: - Private

  private func handleSendReport(arguments: IOUserClientMethodArguments) -> IOReturn {
    // Validate that the caller sent exactly 13 bytes.
    guard arguments.structureInputSize == OpenJoystickUserClient.reportSize else {
      return kIOReturnBadArgument
    }
    guard let inputMem = arguments.structureInput else {
      return kIOReturnBadArgument
    }

    // Pass the memory descriptor directly to handleReport — no copy needed.
    // NOTE: Verify IOUserClientMethodArguments.structureInput type (IOMemoryDescriptor?)
    // and structureInputSize type (UInt64?) against your DriverKit SDK.
    return device?.sendReport(inputMem, length: UInt32(OpenJoystickUserClient.reportSize))
      ?? kIOReturnNotAttached
  }
}
