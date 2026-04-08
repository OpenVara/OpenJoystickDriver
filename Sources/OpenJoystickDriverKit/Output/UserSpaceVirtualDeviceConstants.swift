import Foundation

/// Constants used to identify and exclude OpenJoystickDriver-created virtual devices
/// from the input detection pipeline.
public enum UserSpaceVirtualDeviceConstants {
  /// Serial number assigned to the user-space virtual gamepad (IOHIDUserDevice).
  ///
  /// This is the stable discriminator that lets us avoid input feedback loops.
  public static let serialNumber = "OpenJoystickDriver-UserSpace"

  /// Product string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let product = "OpenJoystickDriver Virtual Gamepad"

  /// Manufacturer string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let manufacturer = "OpenJoystickDriver"

  /// LocationID assigned to the user-space virtual gamepad (IOHIDUserDevice).
  ///
  /// Some HID consumers treat LocationID=0 as "not a real device".
  public static let locationID: UInt32 = VirtualDeviceIdentityConstants.userSpaceLocationID
}
