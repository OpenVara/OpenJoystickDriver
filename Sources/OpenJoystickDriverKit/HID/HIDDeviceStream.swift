import Foundation
import IOKit
import IOKit.hid

/// Watches for HID-class game controllers using Apple's IOKit HID framework.
///
/// Creates an `AsyncStream` of device connect, disconnect, and input report
/// events. IOKit delivers callbacks on the main run loop, and this class
/// forwards them into the stream for safe async consumption.
public final class HIDDeviceStream: @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All IOKit callbacks are scheduled on the main run loop
  // - `continuation` is written only from `deviceEvents()` and `cleanup()`,
  //   both called from the main thread
  // - `deviceEvents()` terminates any existing stream before creating a new one

  private let manager: IOHIDManager
  private var continuation: AsyncStream<HIDDeviceEvent>.Continuation?

  /// VID/PID of the virtual gamepad, used to filter it from the input stream.
  private let virtualVID: UInt16
  private let virtualPID: UInt16

  /// Creates a new stream that matches HID gamepad devices.
  ///
  /// - Parameter virtualProfile: The virtual device profile to exclude from detection.
  public init(virtualProfile: VirtualDeviceProfile = .default) {
    virtualVID = UInt16(virtualProfile.vendorID)
    virtualPID = UInt16(virtualProfile.productID)
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
  }

  /// Returns a live stream of HID device events (connect, disconnect, input report).
  ///
  /// Only one stream can be active at a time. The stream ends when its
  /// consuming task is cancelled.
  public func deviceEvents() -> AsyncStream<HIDDeviceEvent> {
    if continuation != nil { cleanup() }
    return AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in self?.cleanup() }
      self.registerCallbacks()
    }
  }

  // MARK: - Callback registration

  /// Registers IOKit callbacks for device matching, removal, and input reports,
  /// then opens the HID manager on the main run loop.
  private func registerCallbacks() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
    IOHIDManagerRegisterInputReportCallback(manager, Self.inputReportCallback, context)
    // CRITICAL: schedule BEFORE open
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  /// Unschedules the HID manager from the run loop, closes it, and finishes
  /// the async stream.
  private func cleanup() {
    IOHIDManagerUnscheduleFromRunLoop(
      manager,
      CFRunLoopGetMain(),
      CFRunLoopMode.defaultMode.rawValue
    )
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    continuation?.finish()
    continuation = nil
  }

  // MARK: - Event handlers

  /// Reads device properties and yields a `.connected` event into the stream.
  private func handleDeviceAdded(_ device: IOHIDDevice) {
    let vid = deviceProperty(device, kIOHIDVendorIDKey)
    let pid = deviceProperty(device, kIOHIDProductIDKey)

    // Skip our virtual gamepad to prevent a feedback loop.
    // Distinguish from real controllers by checking transport = "Virtual".
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    if UInt16(truncatingIfNeeded: vid) == virtualVID
      && UInt16(truncatingIfNeeded: pid) == virtualPID && transport == "Virtual"
    {
      return
    }

    let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
    let loc = deviceProperty(device, kIOHIDLocationIDKey)
    let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    continuation?.yield(
      .connected(
        vendorID: UInt16(truncatingIfNeeded: vid),
        productID: UInt16(truncatingIfNeeded: pid),
        serialNumber: serial,
        locationID: UInt32(truncatingIfNeeded: loc),
        productName: productName
      )
    )
  }

  /// Yields a `.disconnected` event when IOKit reports a device removal.
  private func handleDeviceRemoved(_ device: IOHIDDevice) {
    let vid = deviceProperty(device, kIOHIDVendorIDKey)
    let pid = deviceProperty(device, kIOHIDProductIDKey)
    let loc = deviceProperty(device, kIOHIDLocationIDKey)
    continuation?.yield(
      .disconnected(
        vendorID: UInt16(truncatingIfNeeded: vid),
        productID: UInt16(truncatingIfNeeded: pid),
        locationID: UInt32(truncatingIfNeeded: loc)
      )
    )
  }

  /// Copies raw report bytes and yields an `.inputReport` event.
  private func handleInputReport(
    locationID: UInt32,
    report: UnsafePointer<UInt8>,
    reportLength: CFIndex
  ) {
    let data = Data(bytes: report, count: reportLength)
    continuation?.yield(.inputReport(locationID: locationID, data: data))
  }

  /// Reads an integer property from an IOKit HID device.
  ///
  /// Returns 0 if missing.
  private func deviceProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  // MARK: - C-convention callbacks

  private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceAdded(device)
  }

  private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved(device)
  }

  private static let inputReportCallback: IOHIDReportCallback = {
    context,
    _,
    sender,
    _,
    _,
    report,
    length in
    guard let context, let sender else { return }
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let loc = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleInputReport(
      locationID: UInt32(truncatingIfNeeded: loc),
      report: report,
      reportLength: length
    )
  }
}
