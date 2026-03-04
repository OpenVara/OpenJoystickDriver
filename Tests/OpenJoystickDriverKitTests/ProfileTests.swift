import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Profile Tests") struct ProfileTests {

  @Test func defaultProfileHasAllButtons() {
    let id = DeviceIdentifier(vendorID: 13623, productID: 4112)
    let profile = Profile.makeDefault(for: id)
    #expect(profile.keyCode(for: .a) == 36)
    #expect(profile.keyCode(for: .b) == 53)
    #expect(profile.keyCode(for: .dpadUp) == 126)
    #expect(profile.vendorID == 13623)
    #expect(profile.productID == 4112)
  }

  @Test func profileRoundTripsJSON() throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let original = Profile.makeDefault(for: id)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Profile.self, from: data)
    #expect(decoded.name == original.name)
    #expect(decoded.vendorID == original.vendorID)
    #expect(decoded.stickDeadzone == original.stickDeadzone)
    #expect(decoded.buttonMappings.count == original.buttonMappings.count)
  }

  @Test func profileKeepsFallbackForUnmappedButton() {
    let id = DeviceIdentifier(vendorID: 1, productID: 1)
    var profile = Profile.makeDefault(for: id)
    profile.buttonMappings.removeValue(forKey: "a")
    #expect(profile.keyCode(for: .a) == 36)
  }

  @Test func profileStoreReturnsDefaultForNewDevice() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: tempDir)
    let id = DeviceIdentifier(vendorID: 999, productID: 888)
    let profile = await store.profile(for: id)
    #expect(profile.vendorID == 999)
    #expect(profile.productID == 888)
    #expect(profile.keyCode(for: .a) == 36)
  }

  @Test func profileStorePersistsAndReloads() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: tempDir)
    let id = DeviceIdentifier(vendorID: 100, productID: 200)
    var profile = Profile.makeDefault(for: id)
    profile.name = "Custom"
    profile.buttonMappings["a"] = 99
    try await store.save(profile)

    let store2 = ProfileStore(directory: tempDir)
    let loaded = await store2.profile(for: id)
    #expect(loaded.name == "Custom")
    #expect(loaded.buttonMappings["a"] == 99)
  }
}
