import Testing

@testable import OpenJoystickDriverKit

@Suite("Device Transport Profile Tests") struct DeviceTransportProfileTests {

  @Test("G7 SE uses default GIP transport profile") func gamesirG7SETransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x82)
    #expect(profile.outputEndpoint == 0x02)
    #expect(!profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 0)
  }

  @Test("G7 SE runtime profile carries Xbox One mapping metadata") func gamesirG7SERuntimeProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.runtimeProfile(for: identifier)

    #expect(profile.parserName == "GIP")
    #expect(profile.protocolVariant == .xboxOne)
    #expect(profile.mappingFlags == ["shareButton"])
    #expect(profile.mappingOptions.contains(.shareButton))
  }

  @Test("Vader 5S uses catalog transport quirks") func vader5STransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 14295, productID: 10241)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x81)
    #expect(profile.outputEndpoint == 0x01)
    #expect(profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 200_000_000)
  }

  @Test("xpad.c Xbox 360 profile batch uses the Xbox360 parser")
  func xpadXbox360ProfileBatch() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 1133, productID: 49693),
      DeviceIdentifier(vendorID: 1133, productID: 49694),
      DeviceIdentifier(vendorID: 1133, productID: 49695),
      DeviceIdentifier(vendorID: 1133, productID: 49730),
      DeviceIdentifier(vendorID: 1848, productID: 18198),
      DeviceIdentifier(vendorID: 1848, productID: 18214),
      DeviceIdentifier(vendorID: 3695, productID: 275),
      DeviceIdentifier(vendorID: 3695, productID: 287),
      DeviceIdentifier(vendorID: 3695, productID: 307)
    ]

    for identifier in identifiers {
      #expect(registry.parserName(for: identifier) == "Xbox360")
      #expect(registry.runtimeProfile(for: identifier).protocolVariant == .xbox360)
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x81)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x01)
    }
  }
}
