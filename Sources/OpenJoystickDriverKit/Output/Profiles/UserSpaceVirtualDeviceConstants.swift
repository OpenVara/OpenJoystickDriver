import Foundation

/// Constants used to identify and exclude OpenJoystickDriver-created virtual devices
/// from the input detection pipeline.
public enum UserSpaceVirtualDeviceConstants {
  /// Serial number prefix assigned to user-space virtual gamepads (IOHIDUserDevice).
  ///
  /// We create one IOHIDUserDevice per connected physical controller, so the
  /// serial number must be unique per virtual device. We keep a stable prefix
  /// so we can reliably filter our own devices from the input pipeline.
  public static let serialPrefix = "OpenJoystickDriver-UserSpace:"

  /// Product string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let product = "OpenJoystickDriver Virtual Gamepad"

  /// Manufacturer string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let manufacturer = "OpenJoystickDriver"

  /// Logical route token used by the bootstrap/shared Compatibility device.
  ///
  /// Dedicated per-consumer devices encode a different token in their serial
  /// number so the foreground monitor can distinguish them in IORegistry.
  public static let sharedRouteToken = "shared"

  /// Returns true when a SerialNumber belongs to an OpenJoystickDriver user-space device.
  public static func isOJDUserSpaceSerial(_ serial: String?) -> Bool {
    guard let serial else { return false }
    return serial.hasPrefix(serialPrefix)
  }

  /// Builds a stable, non-sensitive serial number for a virtual device.
  ///
  /// We hash the physical identifier so we don't leak hardware serial numbers.
  public static func serialNumber(
    for identifier: DeviceIdentifier,
    routeToken: String? = nil
  ) -> String {
    let physicalHash = hex64(fnv1a64(stableKey(for: identifier)))
    guard let routeToken, routeToken != sharedRouteToken else {
      return serialPrefix + physicalHash
    }
    return serialPrefix + routeToken + ":" + physicalHash
  }

  /// Computes a stable LocationID in the OJD namespace for this physical identifier.
  public static func locationID(
    for identifier: DeviceIdentifier,
    routeToken: String? = nil
  ) -> UInt32 {
    let routeKey =
      (routeToken == nil || routeToken == sharedRouteToken) ? "" : "\(routeToken ?? ""):"
    let h = fnv1a64(routeKey + stableKey(for: identifier))
    let low16 = UInt32(truncatingIfNeeded: h & 0xFFFF)
    // Avoid 0/1 because some consumers treat these as special/invalid.
    let safeLow16 = (low16 <= 1) ? (low16 &+ 2) : low16
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | safeLow16
  }

  /// Returns the encoded route token carried by an OJD user-space serial.
  ///
  /// Legacy single-device serials map to ``sharedRouteToken``.
  public static func routeToken(from serial: String?) -> String? {
    guard let serial, serial.hasPrefix(serialPrefix) else { return nil }
    let suffix = String(serial.dropFirst(serialPrefix.count))
    let parts = suffix.split(separator: ":", omittingEmptySubsequences: false)
    if parts.count >= 2, !parts[0].isEmpty {
      return String(parts[0])
    }
    return sharedRouteToken
  }

  /// Returns the stable dedicated route token for one consumer bundle root.
  public static func dedicatedRouteToken(
    forConsumerBundleRootPath bundleRootPath: String
  ) -> String {
    "consumer-" + hex64(fnv1a64(bundleRootPath))
  }

  // MARK: - Private helpers

  private static func stableKey(for identifier: DeviceIdentifier) -> String {
    // Prefer physical serial when available, fall back to locationID.
    // IMPORTANT: this key is only used as hash input; it is not exposed to consumers.
    let sn = identifier.serialNumber ?? ""
    let loc = identifier.locationID.map { "\($0)" } ?? ""
    return "\(identifier.vendorID):\(identifier.productID):\(sn):\(loc)"
  }

  private static func fnv1a64(_ s: String) -> UInt64 {
    // FNV-1a 64-bit (deterministic, tiny, no extra deps).
    var hash: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 {
      hash ^= UInt64(b)
      hash &*= 0x100000001b3
    }
    return hash
  }

  private static func hex64(_ v: UInt64) -> String {
    String(format: "%016llx", v)
  }
}
