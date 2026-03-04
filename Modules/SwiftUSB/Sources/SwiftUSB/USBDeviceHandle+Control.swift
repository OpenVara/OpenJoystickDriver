import CLibUSB
import Foundation

extension USBDeviceHandle {
  func controlTransfer(
    requestType: UInt8,
    request: UInt8,
    value: UInt16,
    index: UInt16,
    data: Data? = nil,
    timeout: UInt32 = 5000
  ) throws -> Data {
    let buffer = [UInt8](data ?? Data())
    let length = buffer.count
    let isInput = (requestType & 0x80) != 0

    guard isInput else {
      let result = buffer.withUnsafeBufferPointer { ptr in
        libusb_control_transfer(
          handle,
          requestType,
          request,
          value,
          index,
          UnsafeMutablePointer(mutating: ptr.baseAddress),
          UInt16(length),
          timeout
        )
      }
      if result < 0 { throw USBError(code: result) }
      return Data()
    }
    var receiveBuffer = [UInt8](repeating: 0, count: max(length, 64))
    let bufferCount = UInt16(receiveBuffer.count)
    let result = receiveBuffer.withUnsafeMutableBufferPointer { ptr in
      libusb_control_transfer(
        handle,
        requestType,
        request,
        value,
        index,
        ptr.baseAddress,
        bufferCount,
        timeout
      )
    }
    if result < 0 { throw USBError(code: result) }
    return Data(receiveBuffer[0..<Int(result)])
  }
}

/// USB bmRequestType bit masks for control transfers (direction and transfer type).
public enum USBRequestType {}

extension USBRequestType {
  public static let `in`: UInt8 = 0x80
  public static let out: UInt8 = 0x00
  public static let standard: UInt8 = 0x00
  public static let `class`: UInt8 = 0x20
  public static let vendor: UInt8 = 0x40
  public static let reserved: UInt8 = 0x60
  public static let device: UInt8 = 0x00
  public static let interface: UInt8 = 0x01
  public static let endpoint: UInt8 = 0x02
  public static let other: UInt8 = 0x03
}

/// Standard USB bRequest codes for control transfers (USB spec table 9-5).
public enum USBRequest {}

extension USBRequest {
  public static let getStatus: UInt8 = 0x00
  public static let clearFeature: UInt8 = 0x01
  public static let setFeature: UInt8 = 0x03
  public static let setAddress: UInt8 = 0x05
  public static let getDescriptor: UInt8 = 0x06
  public static let setDescriptor: UInt8 = 0x07
  public static let getConfiguration: UInt8 = 0x08
  public static let setConfiguration: UInt8 = 0x09
  public static let getInterface: UInt8 = 0x0A
  public static let setInterface: UInt8 = 0x0B
  public static let synchFrame: UInt8 = 0x0C
}

/// USB descriptor type codes (USB spec table 9-5).
public enum USBDescriptorType {}

extension USBDescriptorType {
  public static let device: UInt8 = 0x01
  public static let configuration: UInt8 = 0x02
  public static let string: UInt8 = 0x03
  public static let interface: UInt8 = 0x04
  public static let endpoint: UInt8 = 0x05
  public static let deviceQualifier: UInt8 = 0x06
  public static let otherSpeedConfiguration: UInt8 = 0x07
  public static let interfacePower: UInt8 = 0x08
  public static let otg: UInt8 = 0x09
  public static let debug: UInt8 = 0x0A
  public static let interfaceAssociation: UInt8 = 0x0B
  public static let bos: UInt8 = 0x0F
  public static let deviceCapability: UInt8 = 0x10
  public static let ssEndpointCompanion: UInt8 = 0x30
}
