import CLibUSB
import Foundation

public enum USBEndpointDirection: Int, Sendable {
  case out = 0x00
  case `in` = 0x80

  public static func from(address: UInt8) -> Self { (address & 0x80) != 0 ? .in : .out }
}

public enum USBTransferType: Int, Sendable {
  case control = 0x0
  case isochronous = 0x1
  case bulk = 0x2
  case interrupt = 0x3

  public static func from(attributes: UInt8) -> Self {
    Self(rawValue: Int(attributes & 0x3)) ?? .control
  }
}

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

  public var direction: USBEndpointDirection {
    USBEndpointDirection.from(address: bEndpointAddress)
  }

  public var transferType: USBTransferType { USBTransferType.from(attributes: bmAttributes) }

  public var number: Int { Int(bEndpointAddress & 0x0F) }

  public var address: String { String(format: "0x%02X", bEndpointAddress) }

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

  public func write(data: Data, on handle: USBDeviceHandle) throws -> Int {
    try write(data: data, timeout: 5000, on: handle)
  }

  public func write(data: Data, timeout: UInt32, on handle: USBDeviceHandle) throws -> Int {
    guard direction == .out else {
      throw USBError(code: USBError.errorInvalidParam, context: "Cannot write to IN endpoint")
    }

    return try bulkWrite(on: handle.handle, to: bEndpointAddress, data: data, timeout: timeout)
  }

  public func read(length: Int, on handle: USBDeviceHandle) throws -> Data {
    try read(length: length, timeout: 5000, on: handle)
  }

  public func read(length: Int, timeout: UInt32, on handle: USBDeviceHandle) throws -> Data {
    guard direction == .in else {
      throw USBError(code: USBError.errorInvalidParam, context: "Cannot read from OUT endpoint")
    }

    return try bulkRead(on: handle.handle, from: bEndpointAddress, length: length, timeout: timeout)
  }

  public func clearHalt(on handle: USBDeviceHandle) throws {
    let result = libusb_clear_halt(handle.handle, bEndpointAddress)
    try USBError.check(
      result,
      context: "Clear halt failed for endpoint 0x\(String(format: "%02X", bEndpointAddress))"
    )
  }

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
