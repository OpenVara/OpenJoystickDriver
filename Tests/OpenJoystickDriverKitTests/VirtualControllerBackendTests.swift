import Foundation
import IOKit.hid
import XCTest

@testable import OpenJoystickDriverKit

final class VirtualControllerBackendTests: XCTestCase {
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    XCTAssertTrue(capabilities.isImplemented)
    XCTAssertTrue(capabilities.isSystemWide)
    XCTAssertTrue(capabilities.notes.contains("apple-gamecontroller"))
  }
  func testDriverKitBackendCapability() {
    let backend: any VirtualControllerBackend = DextOutputDispatcher()

    XCTAssertTrue(backend.backendID == .driverKitHID)
    XCTAssertTrue(backend.capabilities.isImplemented)
    XCTAssertTrue(backend.capabilities.isSystemWide)
    XCTAssertTrue(backend.capabilities.requiresEntitlement)
  }
  func testCompatibilityIdentityIDs() {
    XCTAssertTrue(CompatibilityIdentity(rawValue: "generic-hid") == .genericHID)
    XCTAssertTrue(CompatibilityIdentity(rawValue: "sdl2-3") == .sdl2_3)
    XCTAssertTrue(CompatibilityIdentity(rawValue: "apple-gamecontroller") == .appleGameController)
    XCTAssertTrue(CompatibilityIdentity(rawValue: "x360-hid") == .x360HID)
    XCTAssertTrue(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)

    XCTAssertTrue(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }
  func testCompatibilityProfileCatalog() {
    let generic = CompatibilityOutputProfileCatalog.profile(for: .genericHID)
    let sdl = CompatibilityOutputProfileCatalog.profile(for: .sdl2_3)
    let apple = CompatibilityOutputProfileCatalog.profile(for: .appleGameController)
    let x360 = CompatibilityOutputProfileCatalog.profile(for: .x360HID)
    let xone = CompatibilityOutputProfileCatalog.profile(for: .xoneHID)

    XCTAssertTrue(generic.deviceProfile.productID == 0x4449)
    XCTAssertTrue(sdl.deviceProfile.productID == 0x4448)
    XCTAssertTrue(apple.deviceProfile.productID == 0x028E)
    XCTAssertTrue(!generic.isHardwareSpoof)
    XCTAssertTrue(!sdl.isHardwareSpoof)
    XCTAssertTrue(apple.isHardwareSpoof)
    XCTAssertTrue(x360.isHardwareSpoof)
    XCTAssertTrue(x360.deviceProfile.productName == "ASTRO C40 TR Controller")
    XCTAssertTrue(xone.isHardwareSpoof)
    XCTAssertTrue(xone.emitsXboxGuideReport)
  }
  func testCompatibilityIdentitiesRequestDriverKitSeizure() {
    for identity in CompatibilityIdentity.allCases {
      XCTAssertTrue(identity.seizesDriverKitInCompatibilityMode)
    }
  }
  func testGenericReportDpadButtonPolicy() {
    let state = VirtualGamepadState(
      buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
        | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
      hat: .north
    )

    let generic = OJDGenericGamepadFormat().buildInputReport(from: state)
    XCTAssertTrue((UInt16(generic[1]) & 0x88) == 0x88)
    XCTAssertTrue((generic[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)

    let sdl2_3 = OJDGenericGamepadFormat(includesDpadButtonBits: false)
      .buildInputReport(from: state)
    XCTAssertTrue((UInt16(sdl2_3[1]) & 0x78) == 0)
    XCTAssertTrue((UInt16(sdl2_3[1]) & 0x80) == 0x80)
    XCTAssertTrue((sdl2_3[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)
  }
  func testSdlReportUsesButtonDpadAndNeutralTriggers() throws {
    let parsed = try HIDDescriptorReportFormat(descriptor: OJDSDLGamepadFormat().descriptor)
    let neutral = OJDSDLGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let dpad = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
          | GamepadHIDDescriptor.dpadButtonBits(for: .east),
        hat: .northEast
      )
    )
    let triggers = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(leftTrigger: 32_767, rightTrigger: 16_384)
    )

    XCTAssertTrue(parsed.inputReportPayloadSize == 14)
    XCTAssertTrue(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    XCTAssertTrue(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x32,  // LT/Z
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    XCTAssertTrue(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x35,  // RT/Rz
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    XCTAssertTrue(neutral[6] == 0x00)
    XCTAssertTrue(neutral[7] == 0x00)
    XCTAssertTrue(neutral[12] == 0x00)
    XCTAssertTrue(neutral[13] == 0x00)
    XCTAssertTrue((UInt16(dpad[1]) & 0x48) == 0x48)
    XCTAssertTrue(triggers[6] == 0xFF)
    XCTAssertTrue(triggers[7] == 0x7F)
    XCTAssertTrue(triggers[12] == 0x00)
    XCTAssertTrue(triggers[13] == 0x40)
  }
  func testSdlRumbleOutputReportUsesVendorPayload() {
    XCTAssertTrue(SDLGamepadHIDDescriptor.maxOutputReportPayloadSize == 7)
    XCTAssertTrue(OJDSDLGamepadFormat().outputReportPayloadSize == 7)
    XCTAssertTrue(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x06, 0x00, 0xFF,  // vendor-defined output page
      0x09, 0x01,
      0x15, 0x00,
      0x26, 0xFF, 0x00,
      0x75, 0x08,
      0x95, 0x07,
      0x91, 0x02,
    ]))
  }

  func testUserSpaceSDLIdentityAdvertisesReportSizes() {
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .openJoystickDriverSDL2_3,
      format: OJDSDLGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    XCTAssertTrue(inputSize == SDLGamepadHIDDescriptor.reportSize)
    XCTAssertTrue(outputSize == SDLGamepadHIDDescriptor.maxOutputReportPayloadSize)
  }
  func testXbox360FormatDefaultsToJoystickPrimaryUsage() {
    XCTAssertTrue(
      UserSpaceOutputDispatcher.defaultPrimaryUsage(for: Xbox360MacHIDReportFormat())
        == kHIDUsage_GD_Joystick
    )
  }
  func testXbox360GamePadFormatDefaultsToGamePadPrimaryUsage() {
    XCTAssertTrue(
      UserSpaceOutputDispatcher.defaultPrimaryUsage(
        for: Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      ) == kHIDUsage_GD_GamePad
    )
  }
  func testXboxOneCompatibilityFormatDeclaresRumbleOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
      outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )

    XCTAssertTrue(format.inputReportID == 1)
    XCTAssertTrue(format.outputReportID == VirtualRumbleOutputReportParser.xboxOneReportID)
    XCTAssertTrue(
      format.outputReportPayloadSize == VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )
  }
  func testXboxGIPCompatibilityFormatAdvertisesFullOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
      outputReportPayloadSize:
        VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID
    )
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .xboxOneS,
      format: format,
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    XCTAssertTrue(outputSize == 13)
  }
  func testFixedCompatibilityReportHasNoHatAxis() throws {
    let parsed = try HIDDescriptorReportFormat(descriptor: OJDSDLGamepadFormat().descriptor)
    let full = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .south)
          | (1 << GamepadHIDDescriptor.ButtonBit.leftStick.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.rightStick.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.start.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.back.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
        leftTrigger: 32_767,
        rightTrigger: 32_767,
        hat: .south
      )
    )

    XCTAssertTrue(parsed.inputReportPayloadSize == 14)
    XCTAssertTrue(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    XCTAssertTrue(full[1] == 0x97)
    XCTAssertTrue(full[6] == 0xFF)
    XCTAssertTrue(full[7] == 0x7F)
    XCTAssertTrue(full[12] == 0xFF)
    XCTAssertTrue(full[13] == 0x7F)
  }

}

private extension Array where Element: Equatable {
  func containsSequence(_ sequence: [Element]) -> Bool {
    guard !sequence.isEmpty, sequence.count <= count else { return false }
    return indices.dropLast(sequence.count - 1).contains { index in
      self[index..<(index + sequence.count)].elementsEqual(sequence)
    }
  }
}
