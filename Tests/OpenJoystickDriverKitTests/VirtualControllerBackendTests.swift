import Testing

@testable import OpenJoystickDriverKit

@Suite("Virtual Controller Backend Tests") struct VirtualControllerBackendTests {

  @Test("GameController backend is implemented through HID compatibility identity")
  func gameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.notes.contains("apple-gamecontroller"))
  }

  @Test("DriverKit backend reports system-wide entitlement requirement")
  func driverKitBackendCapability() {
    let backend: any VirtualControllerBackend = DextOutputDispatcher()

    #expect(backend.backendID == .driverKitHID)
    #expect(backend.capabilities.isImplemented)
    #expect(backend.capabilities.isSystemWide)
    #expect(backend.capabilities.requiresEntitlement)
  }

  @Test("Compatibility identities expose stable architecture ids only")
  func compatibilityIdentityIDs() {
    #expect(CompatibilityIdentity(rawValue: "generic-hid") == .genericHID)
    #expect(CompatibilityIdentity(rawValue: "sdl2-3") == .sdl2_3)
    #expect(CompatibilityIdentity(rawValue: "apple-gamecontroller") == .appleGameController)
    #expect(CompatibilityIdentity(rawValue: "x360-hid") == .x360HID)
    #expect(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)

    #expect(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }

  @Test("Compatibility profile catalog separates SDL, generic HID, and hardware spoof modes")
  func compatibilityProfileCatalog() {
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
    #expect(xone.isHardwareSpoof)
    #expect(xone.emitsXboxGuideReport)
  }

  @Test("OJD generic report can expose or suppress D-pad button bits")
  func genericReportDpadButtonPolicy() {
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

  @Test("SDL report uses button D-pad and zero-idle trigger axes")
  func sdlReportUsesButtonDpadAndNeutralTriggers() throws {
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


  @Test("Fixed compatibility report has no hat axis and keeps button D-pad")
  func fixedCompatibilityReportHasNoHatAxis() throws {
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
