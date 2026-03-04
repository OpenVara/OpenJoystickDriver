import CLibUSB
import Foundation

/// Describes one alternate setting of a USB interface (USB spec section 9.6.5).
///
/// Obtained from a ``USBConfigurationDescriptor``. Use ``endpoints()`` to list
/// the endpoints available on this interface.
public struct USBInterface: Sendable {
  public let bLength: UInt8
  public let bDescriptorType: UInt8
  public let bInterfaceNumber: UInt8
  public let bAlternateSetting: UInt8
  public let bNumEndpoints: UInt8
  public let bInterfaceClass: UInt8
  public let bInterfaceSubClass: UInt8
  public let bInterfaceProtocol: UInt8
  public let iInterface: UInt8
  public let extraDescriptors: Data?

  private var cachedEndpoints: [USBEndpoint]?

  /// Creates an interface from a raw libusb descriptor pointer.
  public init(descriptor: UnsafePointer<libusb_interface_descriptor>) {
    self.bLength = descriptor.pointee.bLength
    self.bDescriptorType = descriptor.pointee.bDescriptorType
    self.bInterfaceNumber = descriptor.pointee.bInterfaceNumber
    self.bAlternateSetting = descriptor.pointee.bAlternateSetting
    self.bNumEndpoints = descriptor.pointee.bNumEndpoints
    self.bInterfaceClass = descriptor.pointee.bInterfaceClass
    self.bInterfaceSubClass = descriptor.pointee.bInterfaceSubClass
    self.bInterfaceProtocol = descriptor.pointee.bInterfaceProtocol
    self.iInterface = descriptor.pointee.iInterface

    self.extraDescriptors = extractExtraDescriptors(
      from: (descriptor.pointee.extra_length, descriptor.pointee.extra)
    )

    self.cachedEndpoints = nil
  }

  private mutating func loadEndpoints(from descriptor: UnsafePointer<libusb_interface_descriptor>) {
    guard bNumEndpoints > 0 else {
      cachedEndpoints = []
      return
    }

    var endpoints: [USBEndpoint] = []

    for i in 0..<Int(bNumEndpoints) {
      let endpointPtr = descriptor.pointee.endpoint.advanced(by: i)
      let endpointDescriptor = USBEndpoint(descriptor: endpointPtr)
      endpoints.append(endpointDescriptor)
    }

    cachedEndpoints = endpoints
  }

  /// Returns all endpoints for this interface, or an empty array when none are available.
  public func endpoints() -> [USBEndpoint] {
    if let endpoints = cachedEndpoints { return endpoints }
    return []
  }

  /// Returns the endpoint at the given index, or nil when the index is out of range.
  public func endpoint(at index: Int) -> USBEndpoint? {
    guard index >= 0, index < Int(bNumEndpoints) else { return nil }

    if let endpoints = cachedEndpoints, index < endpoints.count { return endpoints[index] }
    return nil
  }

  /// Activates this alternate setting on the given device handle.
  public func setAltSetting(on handle: USBDeviceHandle) throws {
    try handle.setInterfaceAltSetting(
      interface: Int(bInterfaceNumber),
      alternateSetting: Int(bAlternateSetting)
    )
  }

  /// Returns a short single-line description (e.g. `"INTERFACE 0: Human Interface Device"`).
  public func interfaceDescription() -> String {
    var result = "INTERFACE \(bInterfaceNumber)"

    if bAlternateSetting > 0 { result += ", \(bAlternateSetting)" }

    result += ": \(interfaceClassString())"

    return result
  }

  private func interfaceClassString() -> String {
    Self.interfaceClassMap[bInterfaceClass] ?? "Unknown Class"
  }

  private static let interfaceClassMap: [UInt8: String] = [
    0x01: "Audio", 0x02: "Communications", 0x03: "Human Interface Device", 0x05: "Physical",
    0x06: "Image", 0x07: "Printer", 0x08: "Mass Storage", 0x09: "Hub", 0x0A: "CDC Data",
    0x0B: "Smart Card", 0x0E: "Video", 0x0F: "Personal Healthcare", 0x10: "Audio/Video Devices",
    0x11: "Billboard", 0x12: "USB Type-C Bridge", 0x13: "USB Bulk Display", 0x14: "MCT",
    0x15: "USB ENDPOINT", 0x16: "SMC", 0x17: "I3C", 0xDC: "Diagnostic", 0xE0: "Wireless Controller",
    0xEF: "Miscellaneous", 0xFE: "Application Specific", 0xFF: "Vendor Specific",
  ]

  /// Returns a multi-line formatted description with all USB descriptor field values.
  public func detailedDescription() -> String {
    var result = ""

    result += "    \(interfaceDescription()) "
    result += String(repeating: "=", count: max(1, 60 - result.count))
    result += "\n"

    result += String(format: "     %-19s:%#7x (9 bytes)\n", "bLength", bLength)
    result += String(format: "     %-19s:%#7x\n", "bDescriptorType", bDescriptorType)
    result += String(format: "     %-19s:%#7x\n", "bInterfaceNumber", bInterfaceNumber)
    result += String(format: "     %-19s:%#7x\n", "bAlternateSetting", bAlternateSetting)
    result += String(format: "     %-19s:%#7x\n", "bNumEndpoints", bNumEndpoints)
    result += String(
      format: "     %-19s:%#7x %s\n",
      "bInterfaceClass",
      bInterfaceClass,
      interfaceClassString()
    )
    result += String(format: "     %-19s:%#7x\n", "bInterfaceSubClass", bInterfaceSubClass)
    result += String(format: "     %-19s:%#7x\n", "bInterfaceProtocol", bInterfaceProtocol)
    result += String(format: "     %-19s:%#7x\n", "iInterface", iInterface)

    return result
  }
}

extension USBInterface: CustomStringConvertible {
  public var description: String { interfaceDescription() }
}

extension USBInterface: CustomDebugStringConvertible {
  public var debugDescription: String { detailedDescription() }
}

extension USBInterface: Equatable {
  public static func == (lhs: USBInterface, rhs: USBInterface) -> Bool {
    lhs.bInterfaceNumber == rhs.bInterfaceNumber && lhs.bAlternateSetting == rhs.bAlternateSetting
      && lhs.bNumEndpoints == rhs.bNumEndpoints && lhs.bInterfaceClass == rhs.bInterfaceClass
      && lhs.bInterfaceSubClass == rhs.bInterfaceSubClass
      && lhs.bInterfaceProtocol == rhs.bInterfaceProtocol
  }
}

extension USBInterface: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(bInterfaceNumber)
    hasher.combine(bAlternateSetting)
    hasher.combine(bNumEndpoints)
    hasher.combine(bInterfaceClass)
    hasher.combine(bInterfaceSubClass)
    hasher.combine(bInterfaceProtocol)
  }
}
