import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Profile Tests") struct ProfileTests {

  @Test func defaultProfileHasCorrectDefaults() {
    let id = DeviceIdentifier(vendorID: 13623, productID: 4112)
    let profile = Profile.makeDefault(for: id)
    #expect(profile.vendorID == 13623)
    #expect(profile.productID == 4112)
    #expect(profile.name == "Default")
    #expect(profile.stickDeadzone == 0.15)
    // Default profile has no pre-populated button mappings —
    // the dispatcher passes through all buttons as raw HID.
    #expect(profile.buttonMappings.isEmpty)
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

  @Test func profileStoreReturnsDefaultForNewDevice() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ProfileStore(directory: tempDir)
    let id = DeviceIdentifier(vendorID: 999, productID: 888)
    let profile = await store.profile(for: id)
    #expect(profile.vendorID == 999)
    #expect(profile.productID == 888)
    #expect(profile.stickDeadzone == 0.15)
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
