import CLibUSB
import Foundation

/// Namespace for low-level USB utility helpers.
/// Most callers should use ``USBDevice`` and ``USBDeviceHandle`` instead.
public enum USBUtil {}

/// The minimum fields shared by all USB descriptors.
public protocol USBDescriptor {
  /// Total size of this descriptor in bytes.
  var bLength: UInt8 { get }
  /// Descriptor type code (e.g. `0x01` = device, `0x04` = interface).
  var bDescriptorType: UInt8 { get }
}

/// Returns the endpoint number from a raw endpoint address byte (low 4 bits).
public func endpointAddress(_ address: UInt8) -> Int { Int(address & 0x0F) }

/// Returns the data flow direction encoded in an endpoint address byte.
public func endpointDirection(_ address: UInt8) -> USBConstants.EndpointDirection {
  (address & 0x80) != 0 ? .inDirection : .out
}

/// Returns the transfer type encoded in an endpoint bmAttributes byte.
public func endpointType(_ attributes: UInt8) -> USBConstants.EndpointTransferType {
  switch attributes & 0x03 {
  case 0x00: return .control

  case 0x01: return .isochronous

  case 0x02: return .bulk

  case 0x03: return .interrupt

  default: return .control
  }
}
/// Returns the control transfer direction from a bmRequestType byte.
public func controlDirection(_ requestType: UInt8) -> USBConstants.ControlDirection {
  (requestType & 0x80) != 0 ? .inDirection : .out
}

/// Builds a bmRequestType byte from its three component fields.
public func buildRequestType(
  direction: USBConstants.ControlDirection,
  type: USBConstants.ControlRequestType,
  recipient: USBConstants.ControlRecipient
) -> UInt8 { recipient.rawValue | type.rawValue | direction.rawValue }

/// Returns the first descriptor in `container` that satisfies `criteria`, or nil.
public func findDescriptor<T: USBDescriptor>(
  in container: any Sequence<T>,
  matching criteria: (T) -> Bool
) -> T? {
  for descriptor in container where criteria(descriptor) { return descriptor }
  return nil
}

/// Returns the language IDs the device supports for string descriptors.
public func getLanguageIDs(from device: USBDevice) throws -> [UInt16] {
  let handle = try openDeviceHandle(for: device)
  defer { libusb_close(handle) }

  let buffer = try fetchLanguageIDDescriptor(on: handle)
  guard validateDescriptor(buffer, transferResult: buffer.count) else { return [] }

  return extractLanguageIDs(from: buffer)
}

private func openDeviceHandle(for device: USBDevice) throws -> OpaquePointer {
  var handle: OpaquePointer?
  let openResult = libusb_open(device.device, &handle)
  try USBError.check(openResult, context: "Failed to open device for language IDs")

  guard let deviceHandle = handle else {
    throw USBError(message: "Failed to open device for language IDs")
  }

  return deviceHandle
}

private func fetchLanguageIDDescriptor(on handle: OpaquePointer) throws -> [UInt8] {
  var buffer = [UInt8](repeating: 0, count: 254)
  let bufferCount = buffer.count
  let bmRequestType = UInt8(0x80)
  let bRequest = UInt8(0x06)
  let wValue = UInt16(0x03) << 8 | UInt16(0)
  let wIndex = UInt16(0)

  let result = buffer.withUnsafeMutableBufferPointer { ptr in
    libusb_control_transfer(
      handle,
      bmRequestType,
      bRequest,
      wValue,
      wIndex,
      ptr.baseAddress,
      UInt16(bufferCount),
      5000
    )
  }

  try USBError.check(result, context: "Failed to get language ID descriptor")

  guard result >= 4 else { return [] }
  guard result.isMultiple(of: 2) else { return [] }

  return buffer
}

private func extractLanguageIDs(from buffer: [UInt8]) -> [UInt16] {
  guard buffer.count >= 4 else { return [] }

  var languageIDs: [UInt16] = []
  let dataLength = min(buffer.count, Int(buffer[0]))

  for i in stride(from: 2, to: dataLength, by: 2) {
    let langID = UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8)
    languageIDs.append(langID)
  }

  return languageIDs
}

private func validateDescriptor(_ buffer: [UInt8], transferResult: Int) -> Bool {
  guard transferResult >= 4 else { return false }
  guard transferResult.isMultiple(of: 2) else { return false }
  return true
}

/// Reads a string descriptor by index. Returns nil when the index is 0 or decoding fails.
/// Pass `nil` for `languageID` to use the first language the device supports.
public func getString(from device: USBDevice, index: Int, languageID: UInt16? = nil) throws
  -> String?
{
  guard index > 0 else { return nil }

  let deviceHandle = try openDeviceHandleForString(device)
  defer { libusb_close(deviceHandle) }

  let effectiveLangID = try determineLanguageID(device, provided: languageID, handle: deviceHandle)
  let descriptorData = try fetchStringDescriptorData(
    handle: deviceHandle,
    index: index,
    langID: effectiveLangID
  )
  return try decodeUTF16String(from: descriptorData)
}

private func openDeviceHandleForString(_ device: USBDevice) throws -> OpaquePointer {
  var handle: OpaquePointer?
  let openResult = libusb_open(device.device, &handle)
  try USBError.check(openResult, context: "Failed to open device for string descriptor")

  guard let deviceHandle = handle else {
    throw USBError(message: "Failed to open device for string descriptor")
  }

  return deviceHandle
}

private func determineLanguageID(
  _ device: USBDevice,
  provided languageID: UInt16?,
  handle: OpaquePointer
) throws -> UInt16 {
  if let providedLangID = languageID { return providedLangID }

  let langIDs = try getLanguageIDs(from: device)
  guard let firstLangID = langIDs.first else {
    throw USBError(message: "Device has no supported language IDs")
  }

  return firstLangID
}

private func fetchStringDescriptorData(handle: OpaquePointer, index: Int, langID: UInt16) throws
  -> [UInt8]
{
  var buffer = [UInt8](repeating: 0, count: 512)

  let bmRequestType = UInt8(0x80)
  let bRequest = UInt8(0x06)
  let wValue = UInt16(USBConstants.DescriptorType.string.rawValue) << 8 | UInt16(index % 256)
  let wIndex = langID
  let bufferCount = UInt16(buffer.count)

  let result = buffer.withUnsafeMutableBufferPointer { ptr in
    libusb_control_transfer(
      handle,
      bmRequestType,
      bRequest,
      wValue,
      wIndex,
      ptr.baseAddress,
      bufferCount,
      5000
    )
  }

  try USBError.check(result, context: "Failed to get string descriptor")

  guard result >= 2 else { throw USBError(message: "String descriptor too short") }

  return buffer
}

private func decodeUTF16String(from buffer: [UInt8]) throws -> String? {
  let descriptorLength = Int(buffer[0])
  guard descriptorLength >= 2 else { return nil }

  let dataLength = min(buffer.count, Int(descriptorLength & 0xFE))
  guard dataLength >= 4 else { return nil }

  var unicodeChars: [UInt16] = []
  for i in stride(from: 2, to: dataLength, by: 2) {
    let char = UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8)
    unicodeChars.append(char)
  }

  let utf16Data = Data(bytes: unicodeChars, count: unicodeChars.count * MemoryLayout<UInt16>.size)
  guard let str = String(data: utf16Data, encoding: .utf16LittleEndian) else { return nil }

  return str
}

/// Reads a string descriptor using the first language the device supports.
public func getString(from device: USBDevice, index: Int) throws -> String? {
  try getString(from: device, index: index, languageID: nil)
}

/// Allocates a zeroed byte buffer of the given length.
public func createBuffer(length: Int) -> [UInt8] { [UInt8](repeating: 0, count: length) }

/// Releases all claimed interfaces on a handle without closing it.
public func disposeResources(for handle: USBDeviceHandle) {
  for interface in handle.claimedInterfaces {
    let result = libusb_release_interface(handle.handle, Int32(interface))
    if result < 0 {
      print("[SwiftUSB] Failed to release interface \(interface): error code \(result)")
    }
  }
  handle.claimedInterfaces.removeAll()
}

/// Returns the direction bit from an endpoint address byte (raw, not typed).
public func legacyEndpointDirection(_ address: UInt8) -> UInt8 { address & 0x80 }

/// Returns the transfer type bits from a bmAttributes byte (raw, not typed).
public func legacyEndpointType(_ attributes: UInt8) -> UInt8 { attributes & 0x03 }

/// Returns the direction bit from a bmRequestType byte (raw, not typed).
public func legacyControlDirection(_ requestType: UInt8) -> UInt8 { requestType & 0x80 }

/// Builds a bmRequestType byte from raw component bytes.
public func legacyBuildRequestType(direction: UInt8, type: UInt8, recipient: UInt8) -> UInt8 {
  recipient | type | direction
}

/// Reads extra descriptor data from raw memory immediately following a USB descriptor struct.
public func extractExtraDescriptors(from descriptor: UnsafeRawPointer) -> Data? {
  let extraLength = descriptor.load(fromByteOffset: 0, as: Int32.self)
  guard extraLength > 0 else { return nil }
  let extraPointer = descriptor.load(
    fromByteOffset: MemoryLayout<Int32>.size,
    as: UnsafePointer<UInt8>.self
  )
  return Data(bytes: extraPointer, count: Int(extraLength))
}

/// Reads extra descriptor data from a (length, pointer) pair stored in a libusb descriptor struct.
public func extractExtraDescriptors(from info: (Int32, UnsafePointer<UInt8>?)) -> Data? {
  let (extraLength, extraPointer) = info
  guard extraLength > 0, let pointer = extraPointer else { return nil }
  return Data(bytes: pointer, count: Int(extraLength))
}

/// Sends bulk data to an OUT endpoint. Returns the number of bytes written.
public func bulkWrite(
  on handle: OpaquePointer,
  to endpoint: UInt8,
  data: Data,
  timeout: UInt32 = 5000
) throws -> Int {
  var transferred: Int32 = 0
  var buffer = [UInt8](data)

  let result = buffer.withUnsafeMutableBufferPointer { ptr in
    libusb_bulk_transfer(
      handle,
      endpoint,
      ptr.baseAddress,
      Int32(data.count),
      &transferred,
      timeout
    )
  }

  if result < 0 {
    throw USBError(code: result, context: "Bulk write failed to endpoint \(endpoint)")
  }

  return Int(transferred)
}

/// Reads bulk data from an IN endpoint. Returns only the bytes actually received.
public func bulkRead(
  on handle: OpaquePointer,
  from endpoint: UInt8,
  length: Int,
  timeout: UInt32 = 5000
) throws -> Data {
  var buffer = [UInt8](repeating: 0, count: length)
  var transferred: Int32 = 0

  let result = buffer.withUnsafeMutableBufferPointer { ptr in
    libusb_bulk_transfer(handle, endpoint, ptr.baseAddress, Int32(length), &transferred, timeout)
  }

  if result < 0 {
    throw USBError(code: result, context: "Bulk read failed from endpoint \(endpoint)")
  }

  return Data(buffer[0..<Int(transferred)])
}

/// Opens a device handle, runs `operation` with it, then closes the handle automatically.
public func withDeviceHandle<T>(for device: OpaquePointer, _ operation: (OpaquePointer) throws -> T)
  throws -> T
{
  var handle: OpaquePointer?
  let openResult = libusb_open(device, &handle)
  try USBError.check(openResult, context: "Failed to open device handle")

  guard let deviceHandle = handle else {
    throw USBError(message: "Device handle is nil after opening")
  }

  defer { libusb_close(deviceHandle) }

  return try operation(deviceHandle)
}

extension USBDevice {
  func getString(index: Int) throws -> String? { try SwiftUSB.getString(from: self, index: index) }
}
