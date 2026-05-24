import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct VirtualControllerBackendTests {
  @Test
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.notes.contains("apple-gamecontroller"))
  }
  @Test
  func testDriverKitBackendCapability() {
    let backend: any VirtualControllerBackend = DextOutputDispatcher()

    #expect(backend.backendID == .driverKitHID)
    #expect(backend.capabilities.isImplemented)
    #expect(backend.capabilities.isSystemWide)
    #expect(backend.capabilities.requiresEntitlement)
  }
  @Test
  func testCompatibilityIdentityIDs() {
    #expect(CompatibilityIdentity(rawValue: "generic-hid") == .genericHID)
    #expect(CompatibilityIdentity(rawValue: "sdl2-3") == .sdl2_3)
    #expect(CompatibilityIdentity(rawValue: "apple-gamecontroller") == .appleGameController)
    #expect(CompatibilityIdentity(rawValue: "x360-hid") == .x360HID)
    #expect(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)

    #expect(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }
  @Test
  func testCompatibilityProfileCatalog() {
    let generic = CompatibilityOutputProfileCatalog.profile(for: .genericHID)
    let sdl = CompatibilityOutputProfileCatalog.profile(for: .sdl2_3)
    let apple = CompatibilityOutputProfileCatalog.profile(for: .appleGameController)
    let x360 = CompatibilityOutputProfileCatalog.profile(for: .x360HID)
    let xone = CompatibilityOutputProfileCatalog.profile(for: .xoneHID)

    #expect(generic.deviceProfile.productID == 0x4449)
    #expect(sdl.deviceProfile.productID == 0x4448)
    #expect(apple.deviceProfile.productID == 0x028E)
    #expect(!generic.isHardwareSpoof)
    #expect(!sdl.isHardwareSpoof)
    #expect(apple.isHardwareSpoof)
    #expect(x360.isHardwareSpoof)
    #expect(x360.deviceProfile.productName == "ASTRO C40 TR Controller")
    #expect(xone.isHardwareSpoof)
    #expect(xone.emitsXboxGuideReport)
  }
  @Test
  func testCompatibilityIdentitiesRequestDriverKitSeizure() {
    for identity in CompatibilityIdentity.allCases {
      #expect(identity.seizesDriverKitInCompatibilityMode)
    }
  }
  @Test
  func testGenericReportDpadButtonPolicy() {
    let state = VirtualGamepadState(
      buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
        | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
      hat: .north
    )

    let generic = OJDGenericGamepadFormat().buildInputReport(from: state)
    #expect((UInt16(generic[1]) & 0x88) == 0x88)
    #expect((generic[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)

    let sdl2_3 = OJDGenericGamepadFormat(includesDpadButtonBits: false)
      .buildInputReport(from: state)
    #expect((UInt16(sdl2_3[1]) & 0x78) == 0)
    #expect((UInt16(sdl2_3[1]) & 0x80) == 0x80)
    #expect((sdl2_3[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)
  }
  @Test
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

    #expect(parsed.inputReportPayloadSize == 14)
    #expect(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x32,  // LT/Z
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x35,  // RT/Rz
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    #expect(neutral[6] == 0x00)
    #expect(neutral[7] == 0x00)
    #expect(neutral[12] == 0x00)
    #expect(neutral[13] == 0x00)
    #expect((UInt16(dpad[1]) & 0x48) == 0x48)
    #expect(triggers[6] == 0xFF)
    #expect(triggers[7] == 0x7F)
    #expect(triggers[12] == 0x00)
    #expect(triggers[13] == 0x40)
  }
  @Test
  func testSdlRumbleOutputReportUsesVendorPayload() {
    #expect(SDLGamepadHIDDescriptor.maxOutputReportPayloadSize == 7)
    #expect(OJDSDLGamepadFormat().outputReportPayloadSize == 7)
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x06, 0x00, 0xFF,  // vendor-defined output page
      0x09, 0x01,
      0x15, 0x00,
      0x26, 0xFF, 0x00,
      0x75, 0x08,
      0x95, 0x07,
      0x91, 0x02,
    ]))
  }

  @Test

  func testUserSpaceSDLIdentityAdvertisesReportSizes() {
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .openJoystickDriverSDL2_3,
      format: OJDSDLGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(inputSize == SDLGamepadHIDDescriptor.reportSize)
    #expect(outputSize == SDLGamepadHIDDescriptor.maxOutputReportPayloadSize)
  }
  @Test
  func testXbox360FormatDefaultsToJoystickPrimaryUsage() {
    #expect(UserSpaceOutputDispatcher.defaultPrimaryUsage(for: Xbox360MacHIDReportFormat())
        == kHIDUsage_GD_Joystick)
  }
  @Test
  func testXbox360GamePadFormatDefaultsToGamePadPrimaryUsage() {
    #expect(UserSpaceOutputDispatcher.defaultPrimaryUsage(
        for: Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      ) == kHIDUsage_GD_GamePad)
  }
  @Test
  func testXboxOneCompatibilityFormatDeclaresRumbleOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
      outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )

    #expect(format.inputReportID == 1)
    #expect(format.outputReportID == VirtualRumbleOutputReportParser.xboxOneReportID)
    #expect(format.outputReportPayloadSize == VirtualRumbleOutputReportParser.xboxOneReportPayloadSize)
  }
  @Test
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
    #expect(outputSize == 13)
  }
  @Test
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

    #expect(parsed.inputReportPayloadSize == 14)
    #expect(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    #expect(full[1] == 0x97)
    #expect(full[6] == 0xFF)
    #expect(full[7] == 0x7F)
    #expect(full[12] == 0xFF)
    #expect(full[13] == 0x7F)
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
