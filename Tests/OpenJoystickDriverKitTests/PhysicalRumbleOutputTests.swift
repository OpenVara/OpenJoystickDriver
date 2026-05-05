import Testing
import Foundation

@testable import OpenJoystickDriverKit

@Suite("Physical Rumble Output Tests") struct PhysicalRumbleOutputTests {
  @Test("GIP and Xbox 360 parsers expose source-backed physical rumble")
  func sourceBackedParsersExposeRumble() {
    #expect(hasPhysicalRumble(GIPParser()))
    #expect(hasPhysicalRumble(Xbox360Parser()))
  }

  @Test("Parsers without source-backed output do not expose physical rumble")
  func parsersWithoutOutputDoNotExposeRumble() {
    #expect(!hasPhysicalRumble(DS4Parser()))
  }

  @Test("XPC device descriptions default rumble support to false")
  func xpcDescriptionDefaultsRumbleSupportToFalse() {
    let description = XPCDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      parser: "Test",
      connection: "USB",
      serialNumber: nil
    )

    #expect(description.supportsPhysicalRumble == false)
  }

  @Test("XPC device descriptions decode missing rumble support as false")
  func xpcDescriptionDecodesMissingRumbleSupportAsFalse() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "parser": "Test",
        "connection": "USB",
        "serialNumber": null
      }
      """
    let description = try JSONDecoder().decode(XPCDeviceDescription.self, from: Data(json.utf8))

    #expect(description.supportsPhysicalRumble == false)
  }

  private func hasPhysicalRumble(_ parser: any InputParser) -> Bool {
    parser is PhysicalRumbleOutput
  }
}
