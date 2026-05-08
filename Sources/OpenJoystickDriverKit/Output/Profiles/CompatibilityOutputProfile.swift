/// First-class compatibility profiles exposed by the user-space HID backend.
public struct CompatibilityOutputProfile: Equatable, Sendable {
  public let identity: CompatibilityIdentity
  public let deviceProfile: VirtualDeviceProfile
  public let displayName: String
  public let notes: String
  public let isHardwareSpoof: Bool
  public let emitsXboxGuideReport: Bool

  public init(
    identity: CompatibilityIdentity,
    deviceProfile: VirtualDeviceProfile,
    displayName: String,
    notes: String,
    isHardwareSpoof: Bool,
    emitsXboxGuideReport: Bool
  ) {
    self.identity = identity
    self.deviceProfile = deviceProfile
    self.displayName = displayName
    self.notes = notes
    self.isHardwareSpoof = isHardwareSpoof
    self.emitsXboxGuideReport = emitsXboxGuideReport
  }
}

public enum CompatibilityOutputProfileCatalog {
  public static func profile(for identity: CompatibilityIdentity) -> CompatibilityOutputProfile {
    switch identity {
    case .genericHID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .openJoystickDriverGenericHID,
        displayName: "Generic HID",
        notes: "OJD-owned HID GamePad identity for descriptor-driven consumers.",
        isHardwareSpoof: false,
        emitsXboxGuideReport: false
      )
    case .sdl2_3:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .openJoystickDriverSDL2_3,
        displayName: "SDL 2/3",
        notes: "OJD-owned SDL/Steam/PCSX2 identity backed by an explicit SDL mapping.",
        isHardwareSpoof: false,
        emitsXboxGuideReport: false
      )
    case .x360HID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Xbox 360 HID",
        notes: "Experimental Microsoft hardware-spoof profile; descriptor and reports must match consumers exactly.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false
      )
    case .xoneHID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xboxOneS,
        displayName: "Xbox One HID",
        notes: "Experimental Microsoft hardware-spoof profile; SDL may use Xbox-specific paths.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: true
      )
    }
  }
}
