// Sources/OpenJoystickDriverKit/Device/DeviceIdentifier.swift

/// Uniquely identifies  game controller for profile matching and multi-controller support.
///
/// Matching priority:
/// 1. Exact: VID + PID + serial
/// 2. Model: VID + PID (same model controllers share profile)
/// 3. Location: VID + PID + locationID (unstable across reboots, but fallback for controllers without serial)
public struct DeviceIdentifier: Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// USB serial number string. Nil if controller doesn't report one.
  public let serialNumber: String?
  /// USB bus number and device address encoded as (bus << 16 | address).
  /// Used as stable-within-session fallback when no serial is available.
  public let locationID: UInt32?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String? = nil,
    locationID: UInt32? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.serialNumber = serialNumber
    self.locationID = locationID
  }

  /// Returns true if this identifier refers to same physical device (exact match).
  public func exactlyMatches(_ other: Self) -> Bool {
    vendorID == other.vendorID && productID == other.productID && serialNumber != nil
      && serialNumber == other.serialNumber
  }

  /// Returns true if this identifier refers to same model (VID + PID match).
  public func modelMatches(_ other: Self) -> Bool {
    vendorID == other.vendorID && productID == other.productID
  }
}

extension DeviceIdentifier: CustomStringConvertible {
  public var description: String {
    let vid = String(format: "0x%04X", vendorID)
    let pid = String(format: "0x%04X", productID)
    let serial = serialNumber.map { " serial=\($0)" } ?? ""
    let loc = locationID.map { " loc=\($0)" } ?? ""
    return "DeviceIdentifier(VID:\(vid) PID:\(pid)\(serial)\(loc))"
  }
}
