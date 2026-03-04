import CLibUSB
import Foundation

/// A USB device discovered by ``USBContext``.
///
/// Exposes the raw USB descriptor fields (USB spec names, e.g. `idVendor`, `bDeviceClass`)
/// plus methods for opening the device, reading string descriptors, and querying driver state.
/// Call ``open()`` to get a ``USBDeviceHandle`` for sending and receiving data.
public final class USBDevice: @unchecked Sendable {
  let device: OpaquePointer
  public let bLength: UInt8
  public let bDescriptorType: UInt8
  public let bcdUSB: UInt16
  public let bDeviceClass: UInt8
  public let bDeviceSubClass: UInt8
  public let bDeviceProtocol: UInt8
  public let bMaxPacketSize0: UInt8
  public let idVendor: UInt16
  public let idProduct: UInt16
  public let bcdDevice: UInt16
  public let iManufacturer: UInt8
  public let iProduct: UInt8
  public let iSerialNumber: UInt8
  public let bNumConfigurations: UInt8
  public let bus: UInt8
  public let address: UInt8
  public let port: UInt8
  public let speed: USBSpeed

  private var cachedHandle: USBDeviceHandle?

  init(device: OpaquePointer, descriptor: libusb_device_descriptor) {
    self.device = device
    self.bLength = descriptor.bLength
    self.bDescriptorType = descriptor.bDescriptorType
    self.bcdUSB = descriptor.bcdUSB
    self.bDeviceClass = descriptor.bDeviceClass
    self.bDeviceSubClass = descriptor.bDeviceSubClass
    self.bDeviceProtocol = descriptor.bDeviceProtocol
    self.bMaxPacketSize0 = descriptor.bMaxPacketSize0
    self.idVendor = descriptor.idVendor
    self.idProduct = descriptor.idProduct
    self.bcdDevice = descriptor.bcdDevice
    self.iManufacturer = descriptor.iManufacturer
    self.iProduct = descriptor.iProduct
    self.iSerialNumber = descriptor.iSerialNumber
    self.bNumConfigurations = descriptor.bNumConfigurations

    self.bus = libusb_get_bus_number(device)
    self.address = libusb_get_device_address(device)
    self.port = libusb_get_port_number(device)
    self.speed = USBSpeed(libusb_get_device_speed(device))
  }

  public var deviceClass: UInt8 { bDeviceClass }

  public var deviceSubClass: UInt8 { bDeviceSubClass }

  public var deviceProtocol: UInt8 { bDeviceProtocol }

  public var manufacturer: String? {
    guard iManufacturer > 0 else { return nil }
    return nil
  }

  public var product: String? {
    guard iProduct > 0 else { return nil }
    return nil
  }

  public var serialNumber: String? {
    guard iSerialNumber > 0 else { return nil }
    return nil
  }

  /// Opens the device and returns a handle for transfers.
  /// Throws ``USBError`` when the OS denies access or the device cannot be opened.
  public func open() throws -> USBDeviceHandle {
    var handle: OpaquePointer?
    let result = libusb_open(device, &handle)
    try USBError.check(result)
    guard let h = handle else { throw USBError(message: "Failed to open device") }
    return USBDeviceHandle(handle: h)
  }

  /// Opens the device and detaches any kernel driver from interface 0, then returns a handle.
  /// Use this when the OS has a built-in driver loaded for the device (e.g. HID class).
  public func openWithCapture() throws -> USBDeviceHandle {
    var handle: OpaquePointer?
    let result = libusb_open(device, &handle)
    try USBError.check(result)
    guard let h = handle else { throw USBError(message: "Failed to open device") }

    let handleObj = USBDeviceHandle(handle: h)
    try handleObj.detachKernelDriver(interface: 0)
    return handleObj
  }

  /// Returns true when the OS kernel has a driver loaded for the given interface number.
  public func isKernelDriverActive(interface: Int) throws -> Bool {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else {
      throw USBError(message: "Failed to open device for kernel driver check")
    }
    defer { libusb_close(h) }

    let result = libusb_kernel_driver_active(h, Int32(interface))
    try USBError.check(result)
    return result == 1
  }

  /// Resets the device on the USB bus. All open handles become invalid after a reset.
  public func reset() throws {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else { throw USBError(message: "Failed to open device for reset") }
    defer { libusb_close(h) }

    let result = libusb_reset_device(h)
    try USBError.check(result)
  }

  /// Clears a halt/stall condition on the given endpoint address.
  public func clearHalt(endpoint: UInt8) throws {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else { throw USBError(message: "Failed to open device for clear halt") }
    defer { libusb_close(h) }

    let result = libusb_clear_halt(h, endpoint)
    try USBError.check(result)
  }

  /// Reads a string descriptor by its index number.
  /// Pass nil for `langID` to use ASCII encoding (no language selection).
  public func getStringDescriptor(index: Int, langID: UInt16? = nil) throws -> String {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else {
      throw USBError(message: "Failed to open device for string descriptor")
    }
    defer { libusb_close(h) }

    var buffer = [UInt8](repeating: 0, count: 256)

    let result = libusb_get_string_descriptor_ascii(h, UInt8(index), &buffer, 256)

    if result < 0 { try USBError.check(result) }

    let stringData = buffer.prefix(Int(result))
    if let str = String(bytes: Array(stringData), encoding: .utf8) { return str }

    throw USBError(message: "Failed to decode string descriptor")
  }

  /// Reads the manufacturer name string from the device.
  /// Throws when the device has no manufacturer string descriptor.
  public func getManufacturer() throws -> String {
    guard iManufacturer > 0 else { throw USBError(message: "No manufacturer string descriptor") }
    return try getStringDescriptor(index: Int(iManufacturer))
  }

  /// Reads the product name string from the device.
  /// Throws when the device has no product string descriptor.
  public func getProduct() throws -> String {
    guard iProduct > 0 else { throw USBError(message: "No product string descriptor") }
    return try getStringDescriptor(index: Int(iProduct))
  }

  /// Reads the serial number string from the device.
  /// Throws when the device has no serial number string descriptor.
  public func getSerialNumber() throws -> String {
    guard iSerialNumber > 0 else { throw USBError(message: "No serial number string descriptor") }
    return try getStringDescriptor(index: Int(iSerialNumber))
  }

  /// Returns the index of the currently active USB configuration.
  public func getActiveConfiguration() throws -> Int {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else { throw USBError(message: "Failed to open device for configuration") }
    defer { libusb_close(h) }

    var configuration: Int32 = 0
    let result = libusb_get_configuration(h, &configuration)
    try USBError.check(result)
    return Int(configuration)
  }

  /// Reads the configuration descriptor at the given index (0-based).
  public func getConfigurationDescriptor(index: Int) throws -> USBConfigurationDescriptor {
    var handle: OpaquePointer?
    let openResult = libusb_open(device, &handle)
    try USBError.check(openResult)
    guard let h = handle else {
      throw USBError(message: "Failed to open device for configuration descriptor")
    }
    defer { libusb_close(h) }

    var configDesc: UnsafeMutablePointer<libusb_config_descriptor>?
    let result = libusb_get_config_descriptor(device, UInt8(index), &configDesc)
    try USBError.check(result)

    guard let desc = configDesc else {
      throw USBError(message: "Failed to get configuration descriptor")
    }
    defer { libusb_free_config_descriptor(desc) }

    return USBConfigurationDescriptor(descriptor: desc.pointee)
  }

  private func getHandle() throws -> USBDeviceHandle {
    if let handle = cachedHandle, handle.isOpen { return handle }
    let handle = try open()
    cachedHandle = handle
    return handle
  }

  public func read(endpoint: UInt8, length: Int, timeout: UInt32 = 5000) throws -> Data {
    let handle = try getHandle()
    return try handle.readBulk(endpoint: endpoint, length: length, timeout: timeout)
  }

  public func write(endpoint: UInt8, data: Data, timeout: UInt32 = 5000) throws -> Int {
    let handle = try getHandle()
    return try handle.bulkTransfer(endpoint: endpoint, data: data, timeout: timeout)
  }

  public func setConfiguration(_ configuration: Int) throws {
    let handle = try getHandle()
    try handle.setConfiguration(configuration)
  }

  public func getActiveConfiguration() throws -> UInt8 {
    let handle = try getHandle()
    return UInt8(try handle.getConfiguration())
  }

  public func isKernelDriverActiveUsingHandle(interface: Int) throws -> Bool {
    let handle = try getHandle()
    return try handle.isKernelDriverActive(interface: interface)
  }

  public func detachKernelDriver(interface: Int) throws {
    let handle = try getHandle()
    try handle.detachKernelDriver(interface: interface)
  }

  public func claimInterface(_ number: Int) throws {
    let handle = try getHandle()
    try handle.claimInterface(number)
  }

  public func releaseInterface(_ number: Int) throws {
    let handle = try getHandle()
    try handle.releaseInterface(number)
  }

  deinit { cachedHandle = nil }
}

/// USB bus speed reported by libusb.
public enum USBSpeed {
  /// Speed is not known.
  case unknown
  /// USB 1.0 Low Speed (1.5 Mbps).
  case low
  /// USB 1.1 Full Speed (12 Mbps).
  case full
  /// USB 2.0 High Speed (480 Mbps).
  case high
  /// USB 3.0 Super Speed (5 Gbps).
  case superSpeed
  /// USB 3.1 Super Speed+ (10 Gbps).
  case superSpeedPlus

  init(_ libusbSpeed: Int32) {
    if libusbSpeed == Int32(LIBUSB_SPEED_LOW.rawValue) {
      self = .low
    } else if libusbSpeed == Int32(LIBUSB_SPEED_FULL.rawValue) {
      self = .full
    } else if libusbSpeed == Int32(LIBUSB_SPEED_HIGH.rawValue) {
      self = .high
    } else if libusbSpeed == Int32(LIBUSB_SPEED_SUPER.rawValue) {
      self = .superSpeed
    } else if libusbSpeed == Int32(LIBUSB_SPEED_SUPER_PLUS.rawValue) {
      self = .superSpeedPlus
    } else {
      self = .unknown
    }
  }

  public var description: String {
    switch self {
    case .unknown: return "Unknown"

    case .low: return "1.5 Mbps (Low Speed)"

    case .full: return "12 Mbps (Full Speed)"

    case .high: return "480 Mbps (High Speed)"

    case .superSpeed: return "5 Gbps (Super Speed)"

    case .superSpeedPlus: return "10 Gbps (Super Speed +)"
    }
  }
}

/// A parsed USB configuration descriptor (USB spec section 9.6.3).
/// Returned by ``USBDevice/getConfigurationDescriptor(index:)``.
public struct USBConfigurationDescriptor: @unchecked Sendable {
  let descriptor: libusb_config_descriptor

  init(descriptor: libusb_config_descriptor) { self.descriptor = descriptor }

  public var bLength: UInt8 { descriptor.bLength }

  public var bDescriptorType: UInt8 { descriptor.bDescriptorType }

  public var wTotalLength: UInt16 { descriptor.wTotalLength }

  public var bNumInterfaces: UInt8 { descriptor.bNumInterfaces }

  public var bConfigurationValue: UInt8 { descriptor.bConfigurationValue }

  public var iConfiguration: UInt8 { descriptor.iConfiguration }

  public var bmAttributes: UInt8 { descriptor.bmAttributes }

  public var maxPower: UInt8 { descriptor.MaxPower }
}

extension USBDevice {
  /// Returns all connected USB devices matching the given filters.
  /// Creates a temporary ``USBContext`` internally; prefer a shared context for repeated calls.
  public static func findAll(
    vendorId: UInt16? = nil,
    productId: UInt16? = nil,
    deviceClass: UInt8? = nil
  ) async throws -> [USBDevice] {
    let context = try USBContext()
    var devices: [USBDevice] = []
    for await device in context.findDevices(
      vendorId: vendorId,
      productId: productId,
      deviceClass: deviceClass,
      findAll: true
    ) { devices.append(device) }
    return devices
  }

  /// Returns the first connected USB device matching the given filters, or nil.
  /// Creates a temporary ``USBContext`` internally; prefer a shared context for repeated calls.
  public static func find(
    vendorId: UInt16? = nil,
    productId: UInt16? = nil,
    deviceClass: UInt8? = nil
  ) async throws -> USBDevice? {
    let context = try USBContext()
    for await device in context.findDevices(
      vendorId: vendorId,
      productId: productId,
      deviceClass: deviceClass,
      findAll: false
    ) { return device }
    return nil
  }
}
