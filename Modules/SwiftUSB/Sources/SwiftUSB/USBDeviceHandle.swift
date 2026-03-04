import CLibUSB
import Foundation

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

  public var isOpen: Bool { isHandleOpen }

  public func claimInterface(_ number: Int) throws {
    let result = libusb_claim_interface(handle, Int32(number))
    try USBError.check(result)
    claimedInterfaces.insert(number)
  }

  public func releaseInterface(_ number: Int) throws {
    let result = libusb_release_interface(handle, Int32(number))
    try USBError.check(result)
    claimedInterfaces.remove(number)
  }

  public func detachKernelDriver(interface: Int) throws {
    let result = libusb_detach_kernel_driver(handle, Int32(interface))
    if result != 0 && result != -5 { try USBError.check(result) }
  }

  public func isKernelDriverActive(interface: Int) throws -> Bool {
    let result = libusb_kernel_driver_active(handle, Int32(interface))
    try USBError.check(result)
    return result == 1
  }

  public func setConfiguration(_ configuration: Int) throws {
    let result = libusb_set_configuration(handle, Int32(configuration))
    try USBError.check(result)
  }

  public func getConfiguration() throws -> Int {
    var configuration: Int32 = 0
    let result = libusb_get_configuration(handle, &configuration)
    try USBError.check(result)
    return Int(configuration)
  }

  public func setInterfaceAltSetting(interface: Int, alternateSetting: Int) throws {
    let result = libusb_set_interface_alt_setting(handle, Int32(interface), Int32(alternateSetting))
    try USBError.check(result)
  }

  public func clearHalt(endpoint: UInt8) throws {
    let result = libusb_clear_halt(handle, endpoint)
    try USBError.check(result)
  }

  public func resetDevice() throws {
    let result = libusb_reset_device(handle)
    if result < 0 { try USBError.check(result) } else { isHandleOpen = false }
  }
}
