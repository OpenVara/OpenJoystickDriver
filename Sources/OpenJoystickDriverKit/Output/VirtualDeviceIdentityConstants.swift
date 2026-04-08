import Foundation

/// Stable identity constants for OpenJoystickDriver-created virtual HID devices.
///
/// These values are used to:
/// - disambiguate our virtual devices from real controllers with the same VID/PID
/// - avoid ambiguous `LocationID=0/1` heuristics in some HID consumers
public enum VirtualDeviceIdentityConstants {
  /// LocationID used by the DriverKit virtual gamepad (dext).
  ///
  /// Must be non-zero and stable across launches so consumers can treat it like
  /// a "real" device and to avoid collisions with common physical LocationIDs.
  public static let driverKitLocationID: UInt32 = 0x4F4A_4401  // "OJD" namespace

  /// Serial number assigned by the DriverKit virtual gamepad (dext).
  ///
  /// This is safe to expose (not a hardware serial) and is used only to avoid
  /// ambiguous matches when multiple devices share the same VID/PID.
  public static let driverKitSerialNumber = "OpenJoystickDriver-DriverKit"

  /// LocationID used by the user-space IOHIDUserDevice virtual gamepad.
  public static let userSpaceLocationID: UInt32 = 0x4F4A_4402  // "OJD" namespace
}

