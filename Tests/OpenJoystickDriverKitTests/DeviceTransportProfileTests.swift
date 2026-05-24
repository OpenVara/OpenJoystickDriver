import Testing

@testable import OpenJoystickDriverKit

struct DeviceTransportProfileTests {
  @Test
  func testGamesirG7SETransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x82)
    #expect(profile.outputEndpoint == 0x02)
    #expect(!profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 0)
  }
  @Test
  func testGamesirG7SERuntimeProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.runtimeProfile(for: identifier)

    #expect(profile.parserName == "GIP")
    #expect(profile.protocolVariant == .xboxOne)
    #expect(profile.mappingFlags == ["shareButton"])
    #expect(profile.mappingOptions.contains(.shareButton))
  }
  @Test
  func testVader5STransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 14295, productID: 10241)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x81)
    #expect(profile.outputEndpoint == 0x01)
    #expect(profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 200_000_000)
  }
  @Test
  func testXpadXbox360ProfileBatch() {
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
      DeviceIdentifier(vendorID: 3695, productID: 307),
    ]

    for identifier in identifiers {
      #expect(registry.parserName(for: identifier) == "Xbox360")
      #expect(registry.runtimeProfile(for: identifier).protocolVariant == .xbox360)
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x81)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x01)
    }
  }
  @Test
  func testXpadXboxOneProfileBatch() {
    let registry = ParserRegistry()
    let defaultSequence = GIPStartupPacket.defaultSequence
    let cases: [(DeviceIdentifier, [GIPStartupPacket], [String])] = [
      (
        DeviceIdentifier(vendorID: 1118, productID: 746),
        [.powerOn, .xboxOneSInit, .ledOn, .authDone],
        ["shareButton"]
      ),
      (
        DeviceIdentifier(vendorID: 1118, productID: 2816),
        [.powerOn, .xboxOneSInit, .extraInput, .ledOn, .authDone],
        ["shareButton", "paddles", "profileButton"]
      ),
      (
        DeviceIdentifier(vendorID: 3853, productID: 103),
        [.horiAck, .powerOn, .ledOn, .authDone],
        []
      ),
      (DeviceIdentifier(vendorID: 3695, productID: 676), defaultSequence, []),
      (DeviceIdentifier(vendorID: 3695, productID: 678), defaultSequence, []),
      (DeviceIdentifier(vendorID: 3695, productID: 683), defaultSequence, []),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21530),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd],
        []
      ),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21546),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd],
        []
      ),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21562),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd],
        []
      ),
    ]

    for (identifier, startupPackets, mappingFlags) in cases {
      let profile = registry.runtimeProfile(for: identifier)
      #expect(registry.parserName(for: identifier) == "GIP")
      #expect(profile.protocolVariant == .xboxOne)
      #expect(profile.gipStartupPackets == startupPackets)
      #expect(profile.mappingFlags == mappingFlags)
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
    }
  }
}
