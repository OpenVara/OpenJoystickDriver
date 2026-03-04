import CLibUSB
import Foundation

/// An open handle to a USB device, used for all data transfers.
///
/// Created by ``USBDevice/open()`` or ``USBDevice/openWithCapture()``.
/// All claimed interfaces are released and the libusb handle is closed automatically on dealloc.
public final class USBDeviceHandle: @unchecked Sendable {
  let handle: OpaquePointer
  var claimedInterfaces: Set<Int>

  private var isHandleOpen: Bool = true

  init(handle: OpaquePointer) {
    self.handle = handle
    self.claimedInterfaces = []
  }

  deinit {
    for interface in claimedInterfaces { libusb_release_interface(handle, Int32(interface)) }
    libusb_close(handle)
    isHandleOpen = false
  }

  /// True while the underlying libusb handle is valid (before ``resetDevice()`` or dealloc).
  public var isOpen: Bool { isHandleOpen }

  /// Claims an interface so this handle can send and receive data on it.
  /// Must be called before any interrupt or bulk transfers on that interface.
  public func claimInterface(_ number: Int) throws {
    let result = libusb_claim_interface(handle, Int32(number))
    try USBError.check(result)
    claimedInterfaces.insert(number)
  }

  /// Releases a previously claimed interface.
  public func releaseInterface(_ number: Int) throws {
    let result = libusb_release_interface(handle, Int32(number))
    try USBError.check(result)
    claimedInterfaces.remove(number)
  }

  /// Detaches the OS kernel driver from an interface so this process can claim it.
  /// Silently succeeds when no kernel driver is loaded (libusb error -5 is ignored).
  public func detachKernelDriver(interface: Int) throws {
    let result = libusb_detach_kernel_driver(handle, Int32(interface))
    if result != 0 && result != -5 { try USBError.check(result) }
  }

  /// Returns true when the OS kernel has a driver loaded on the given interface.
  public func isKernelDriverActive(interface: Int) throws -> Bool {
    let result = libusb_kernel_driver_active(handle, Int32(interface))
    try USBError.check(result)
    return result == 1
  }

  /// Sets the active USB configuration on the device.
  public func setConfiguration(_ configuration: Int) throws {
    let result = libusb_set_configuration(handle, Int32(configuration))
    try USBError.check(result)
  }

  /// Returns the index of the currently active USB configuration.
  public func getConfiguration() throws -> Int {
    var configuration: Int32 = 0
    let result = libusb_get_configuration(handle, &configuration)
    try USBError.check(result)
    return Int(configuration)
  }

  /// Selects an alternate setting for an interface.
  public func setInterfaceAltSetting(interface: Int, alternateSetting: Int) throws {
    let result = libusb_set_interface_alt_setting(handle, Int32(interface), Int32(alternateSetting))
    try USBError.check(result)
  }

  /// Clears a halt/stall condition on the given endpoint.
  public func clearHalt(endpoint: UInt8) throws {
    let result = libusb_clear_halt(handle, endpoint)
    try USBError.check(result)
  }

  /// Resets the device. This handle becomes invalid after the call.
  public func resetDevice() throws {
    let result = libusb_reset_device(handle)
    if result < 0 { try USBError.check(result) } else { isHandleOpen = false }
  }
}
