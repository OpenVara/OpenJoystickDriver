import Testing

@testable import OpenJoystickDriverKit

@Suite("Virtual Controller Backend Tests") struct VirtualControllerBackendTests {

  @Test("GameController virtual backend is tracked as unsupported system-wide output")
  func gameControllerVirtualBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerVirtualCapabilities

    #expect(!capabilities.isImplemented)
    #expect(!capabilities.isSystemWide)
    #expect(capabilities.notes.contains("GCVirtualController"))
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
    #expect(CompatibilityIdentity(rawValue: "sdl-macos") == .sdlMacOS)
    #expect(CompatibilityIdentity(rawValue: "x360-hid") == .x360HID)
    #expect(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)

    #expect(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }

  @Test("Compatibility profile catalog separates SDL, generic HID, and hardware spoof modes")
  func compatibilityProfileCatalog() {
    let generic = CompatibilityOutputProfileCatalog.profile(for: .genericHID)
    let sdl = CompatibilityOutputProfileCatalog.profile(for: .sdlMacOS)
    let x360 = CompatibilityOutputProfileCatalog.profile(for: .x360HID)
    let xone = CompatibilityOutputProfileCatalog.profile(for: .xoneHID)

    #expect(generic.deviceProfile.productID == 0x4449)
    #expect(sdl.deviceProfile.productID == 0x4448)
    #expect(!generic.isHardwareSpoof)
    #expect(!sdl.isHardwareSpoof)
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

    let sdlMacOS = OJDGenericGamepadFormat(includesDpadButtonBits: false).buildInputReport(from: state)
    #expect((UInt16(sdlMacOS[1]) & 0x78) == 0)
    #expect((UInt16(sdlMacOS[1]) & 0x80) == 0x80)
    #expect((sdlMacOS[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)
  }
}
