import Foundation

/// USB specification constants organized by category.
///
/// All values match the USB 2.0/3.x specification.
public enum USBConstants {
  public static let usbVersion: UInt16 = 0x0200
  // swiftlint:disable:next identifier_name
  public static let usbVersion3_0: UInt16 = 0x0300
  // swiftlint:disable:next identifier_name
  public static let usbVersion3_1: UInt16 = 0x0310

  /// Standard USB descriptor type codes (USB spec table 9-5).
  public enum DescriptorType: UInt8 {
    case device = 0x01
    case configuration = 0x02
    case string = 0x03
    case interface = 0x04
    case endpoint = 0x05
    case deviceQualifier = 0x06
    case otherSpeedConfiguration = 0x07
    case interfacePower = 0x08
    case otg = 0x09
    case debug = 0x0A
    case bos = 0x0F
    case deviceCapability = 0x10
    case superspeedEndpointCompanion = 0x30
    case superspeedIsoEndpointCompanion = 0x31
  }

  /// USB 2.0 descriptor type codes (subset of ``DescriptorType``).
  public enum LegacyDescriptorType: UInt8 {
    case device = 0x01
    case configuration = 0x02
    case string = 0x03
    case interface = 0x04
    case endpoint = 0x05
  }

  /// HID class descriptor type codes (HID spec section 7.1).
  public enum HIDDescriptorType: UInt8 {
    case hid = 0x21
    case report = 0x22
    case physical = 0x23
  }

  /// Hub class descriptor type code.
  public enum HubDescriptorType: UInt8 { case hub = 0x29 }

  /// Endpoint address direction bit (bit 7 of bEndpointAddress).
  public enum EndpointDirection: UInt8 {
    case out = 0x00
    case inDirection = 0x80
  }

  public static func endpointDirectionToControlDirection(_ direction: EndpointDirection) -> UInt8 {
    switch direction {
    case .inDirection: return 0x80

    case .out: return 0x00
    }
  }

  /// Endpoint transfer type (low 2 bits of bmAttributes).
  public enum EndpointTransferType: UInt8 {
    case control = 0x00
    case isochronous = 0x01
    case bulk = 0x02
    case interrupt = 0x03
  }

  /// Bit masks for extracting fields from endpoint address and attribute bytes.
  public enum EndpointMask: UInt8 {
    case addressMask = 0x0F
    case directionMask = 0x80
    case transferTypeMask = 0x03
  }

  /// bmRequestType type field values (bits 5-6).
  public enum ControlRequestType: UInt8 {
    case standard = 0x00
    case classType = 0x20
    case vendor = 0x40
    case reserved = 0x60
  }

  /// bmRequestType recipient field values (bits 0-4).
  public enum ControlRecipient: UInt8 {
    case device = 0
    case interface = 1
    case endpoint = 2
    case other = 3
  }

  /// bmRequestType direction bit (bit 7).
  public enum ControlDirection: UInt8 {
    case out = 0x00
    case inDirection = 0x80
  }

  /// Builds a bmRequestType byte from its three component fields.
  public static func makeRequestType(
    direction: ControlDirection,
    type: ControlRequestType,
    recipient: ControlRecipient
  ) -> UInt8 { direction.rawValue | type.rawValue | recipient.rawValue }

  /// Standard USB feature selector values for ClearFeature/SetFeature requests.
  public enum FeatureSelector: UInt8 {
    case endpointHalt = 0
    case deviceRemoteWakeup = 1
    case testMode = 2
    case u1Enable = 48
    case u2Enable = 49
    case ltmEnable = 50
  }

  /// USB device class codes (USB spec table 3-1).
  public enum DeviceClass: UInt8 {
    case audio = 1
    case communications = 2
    case humanInterfaceDevice = 3
    case physical = 5
    case image = 6
    case printer = 7
    case massStorage = 8
    case hub = 9
    case cdcData = 10
    case smartCard = 11
    case contentSecurity = 13
    case video = 14
    case wirelessController = 0xE0
    case miscellaneous = 0xEF
    case applicationSpecific = 0xFE
    case vendorSpecific = 0xFF
  }

  /// Standard USB request codes (USB spec table 9-5).
  public enum StandardRequest: UInt8 {
    case getStatus = 0
    case clearFeature = 1
    case reserved1 = 2
    case setFeature = 3
    case reserved2 = 4
    case setAddress = 5
    case getDescriptor = 6
    case setDescriptor = 7
    case getConfiguration = 8
    case setConfiguration = 9
    case getInterface = 10
    case setInterface = 11
    case synchFrame = 12
  }

  /// bmRequestType recipient values (USB spec table 9-3).
  public enum RequestRecipient: UInt8 {
    case device = 0
    case interface = 1
    case endpoint = 2
    case other = 3
  }

  /// bmRequestType type values (USB spec table 9-3).
  public enum RequestType: UInt8 {
    case standard = 0
    case classType = 32
    case vendor = 64
    case reserved = 96
  }

  /// Implementation-defined limits for USB descriptor structures.
  public enum Limits {
    /// Maximum number of alternate settings per interface.
    public static let maxAlternateSetting: Int = 128
    /// Maximum number of configurations per device.
    public static let maxConfiguration: Int = 8
    /// Maximum number of endpoints per device.
    public static let maxEndpoints: Int = 32
    /// Maximum number of interfaces per configuration.
    public static let maxInterfaces: Int = 32
  }

  /// USB bus speed values.
  public enum USBSpeed: UInt8 {
    case lowSpeed = 1
    case fullSpeed = 2
    case highSpeed = 3
    case superSpeed = 4
    case superSpeedPlus = 5
  }
}
