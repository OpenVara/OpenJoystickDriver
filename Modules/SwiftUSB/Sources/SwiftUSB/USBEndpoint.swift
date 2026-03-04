import CLibUSB
import Foundation

/// Data flow direction of a USB endpoint.
public enum USBEndpointDirection: Int, Sendable {
  /// Host-to-device (write).
  case out = 0x00
  /// Device-to-host (read).
  case `in` = 0x80

  /// Infers the direction from the raw endpoint address byte.
  public static func from(address: UInt8) -> Self { (address & 0x80) != 0 ? .in : .out }
}

/// USB transfer type for an endpoint.
public enum USBTransferType: Int, Sendable {
  case control = 0x0
  case isochronous = 0x1
  case bulk = 0x2
  case interrupt = 0x3

  /// Infers the transfer type from the raw bmAttributes byte.
  public static func from(attributes: UInt8) -> Self {
    Self(rawValue: Int(attributes & 0x3)) ?? .control
  }
}

/// Describes one endpoint in a USB interface (USB spec section 9.6.6).
public struct USBEndpoint: Sendable {
  public let bLength: UInt8
  public let bDescriptorType: UInt8
  public let bEndpointAddress: UInt8
  public let bmAttributes: UInt8
  public let wMaxPacketSize: UInt16
  public let bInterval: UInt8
  public let bRefresh: UInt8
  public let bSynchAddress: UInt8
  public let extraDescriptors: Data?

  /// Data flow direction decoded from `bEndpointAddress`.
  public var direction: USBEndpointDirection {
    USBEndpointDirection.from(address: bEndpointAddress)
  }

  /// Transfer type decoded from `bmAttributes`.
  public var transferType: USBTransferType { USBTransferType.from(attributes: bmAttributes) }

  /// Endpoint number - the low 4 bits of `bEndpointAddress`.
  public var number: Int { Int(bEndpointAddress & 0x0F) }

  /// Endpoint address as a formatted hex string (e.g. `"0x82"`).
  public var address: String { String(format: "0x%02X", bEndpointAddress) }

  /// Maximum packet size in bytes, with high-speed transaction bits masked out.
  public var maxPacketSize: Int { Int(wMaxPacketSize & 0x07FF) }

  public static func from(address: UInt8) -> Self {
    Self(
      bLength: 7,
      bDescriptorType: 5,
      bEndpointAddress: address,
      bmAttributes: 0,
      wMaxPacketSize: 64,
      bInterval: 0,
      bRefresh: 0,
      bSynchAddress: 0,
      extraDescriptors: nil
    )
  }

  public static func from(attributes: UInt8) -> Self {
    Self(
      bLength: 7,
      bDescriptorType: 5,
      bEndpointAddress: 0,
      bmAttributes: attributes,
      wMaxPacketSize: 64,
      bInterval: 10,
      bRefresh: 0,
      bSynchAddress: 0,
      extraDescriptors: nil
    )
  }

  public init(
    bLength: UInt8,
    bDescriptorType: UInt8,
    bEndpointAddress: UInt8,
    bmAttributes: UInt8,
    wMaxPacketSize: UInt16,
    bInterval: UInt8,
    bRefresh: UInt8,
    bSynchAddress: UInt8,
    extraDescriptors: Data?
  ) {
    self.bLength = bLength
    self.bDescriptorType = bDescriptorType
    self.bEndpointAddress = bEndpointAddress
    self.bmAttributes = bmAttributes
    self.wMaxPacketSize = wMaxPacketSize
    self.bInterval = bInterval
    self.bRefresh = bRefresh
    self.bSynchAddress = bSynchAddress
    self.extraDescriptors = extraDescriptors
  }

  public init(descriptor: UnsafePointer<libusb_endpoint_descriptor>) {
    let address = descriptor.pointee.bEndpointAddress
    let attributes = descriptor.pointee.bmAttributes
    let extraLength = Int(descriptor.pointee.extra_length)
    let extraPointer = descriptor.pointee.extra

    self.bLength = descriptor.pointee.bLength
    self.bDescriptorType = descriptor.pointee.bDescriptorType
    self.bEndpointAddress = address
    self.bmAttributes = attributes
    self.wMaxPacketSize = descriptor.pointee.wMaxPacketSize
    self.bInterval = descriptor.pointee.bInterval
    self.bRefresh = descriptor.pointee.bRefresh
    self.bSynchAddress = descriptor.pointee.bSynchAddress

    var extraData: Data?
    if let pointer = extraPointer, extraLength > 0 {
      extraData = Data(UnsafeBufferPointer(start: pointer, count: extraLength))
    }
    self.extraDescriptors = extraData
  }

  /// Writes data to this OUT endpoint via a bulk transfer (5 second timeout).
  public func write(data: Data, on handle: USBDeviceHandle) throws -> Int {
    try write(data: data, timeout: 5000, on: handle)
  }

  /// Writes data to this OUT endpoint via a bulk transfer with the given timeout (milliseconds).
  public func write(data: Data, timeout: UInt32, on handle: USBDeviceHandle) throws -> Int {
    guard direction == .out else {
      throw USBError(code: USBError.errorInvalidParam, context: "Cannot write to IN endpoint")
    }

    return try bulkWrite(on: handle.handle, to: bEndpointAddress, data: data, timeout: timeout)
  }

  /// Reads up to `length` bytes from this IN endpoint via a bulk transfer (5 second timeout).
  public func read(length: Int, on handle: USBDeviceHandle) throws -> Data {
    try read(length: length, timeout: 5000, on: handle)
  }

  /// Reads up to `length` bytes from this IN endpoint via a bulk transfer with the given timeout (milliseconds).
  public func read(length: Int, timeout: UInt32, on handle: USBDeviceHandle) throws -> Data {
    guard direction == .in else {
      throw USBError(code: USBError.errorInvalidParam, context: "Cannot read from OUT endpoint")
    }

    return try bulkRead(on: handle.handle, from: bEndpointAddress, length: length, timeout: timeout)
  }

  /// Clears a halt/stall condition on this endpoint.
  public func clearHalt(on handle: USBDeviceHandle) throws {
    let result = libusb_clear_halt(handle.handle, bEndpointAddress)
    try USBError.check(
      result,
      context: "Clear halt failed for endpoint 0x\(String(format: "%02X", bEndpointAddress))"
    )
  }

  /// Returns a short description (e.g. `"ENDPOINT 0x82: INTERRUPT IN"`).
  public func debugDescription() -> String {
    let directionStr = direction == .in ? "IN" : "OUT"
    let typeStr = transferTypeString()

    return String(format: "ENDPOINT 0x%02X: %@ %@", bEndpointAddress, typeStr, directionStr)
  }

  private func transferTypeString() -> String {
    switch transferType {
    case .control: return "CONTROL"

    case .isochronous: return "ISOCHRONOUS"

    case .bulk: return "BULK"

    case .interrupt: return "INTERRUPT"
    }
  }

  private func extractExtraDescriptors(from raw: (Int, UnsafePointer<UInt8>?)) -> Data? {
    guard let pointer = raw.1, raw.0 > 0 else { return nil }

    return Data(UnsafeBufferPointer(start: pointer, count: raw.0))
  }
}

extension USBEndpoint: CustomStringConvertible {
  public var description: String { debugDescription() }
}

extension USBEndpoint: Equatable {
  public static func == (lhs: USBEndpoint, rhs: USBEndpoint) -> Bool {
    lhs.bEndpointAddress == rhs.bEndpointAddress && lhs.bmAttributes == rhs.bmAttributes
      && lhs.wMaxPacketSize == rhs.wMaxPacketSize && lhs.bInterval == rhs.bInterval
  }
}
