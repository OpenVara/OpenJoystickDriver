/// Identifies a game controller for profile matching and multi-controller support.
///
/// Three levels of matching, from most specific to least:
/// 1. **Exact** - vendor ID + product ID + serial number. Matches one physical device.
/// 2. **Model** - vendor ID + product ID only. All controllers of the same model share a profile.
/// 3. **Location** - vendor ID + product ID + location ID. A fallback for controllers that
///    do not report a serial number. Location IDs can change when you unplug and replug.
public struct DeviceIdentifier: Hashable, Sendable {
  /// Vendor ID (VID) - identifies who made the controller (e.g. 0x3537 = Gamesir).
  public let vendorID: UInt16
  /// Product ID (PID) - identifies which model of controller (e.g. 0x1010 = G7 SE).
  public let productID: UInt16
  /// USB serial number reported by the controller.
  ///
  /// Nil if the controller does not provide one.
  public let serialNumber: String?
  /// USB location encoded as `(bus << 16 | address)`.
  ///
  /// Stable within a single session but may change after reboot or replug.
  /// Used as a fallback when serial is unavailable.
  public let locationID: UInt32?

  /// Creates a new DeviceIdentifier.
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

  /// Returns true when both identifiers point to the same physical device.
  ///
  /// Requires matching vendor ID, product ID, and a non-nil serial number.
  public func exactlyMatches(_ other: Self) -> Bool {
    vendorID == other.vendorID && productID == other.productID && serialNumber != nil
      && serialNumber == other.serialNumber
  }

  /// Returns true when both identifiers have the same vendor and product ID.
  ///
  /// Regardless of serial number or location. Used for model-level profile matching.
  public func modelMatches(_ other: Self) -> Bool {
    vendorID == other.vendorID && productID == other.productID
  }
}

extension DeviceIdentifier: CustomStringConvertible {
  /// Returns a human-readable representation of the device identifier.
  public var description: String {
    let vid = String(format: "0x%04X", vendorID)
    let pid = String(format: "0x%04X", productID)
    let serial = serialNumber.map { " serial=\($0)" } ?? ""
    let loc = locationID.map { " loc=\($0)" } ?? ""
    return "DeviceIdentifier(VID:\(vid) PID:\(pid)\(serial)\(loc))"
  }
}
