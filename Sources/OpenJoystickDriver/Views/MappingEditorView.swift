import OpenJoystickDriverKit
import SwiftUI

struct MappingEditorView: View {
  let device: DeviceViewModel
  @EnvironmentObject var model: AppModel
  @State private var profile: Profile?
  @State private var saveError: String?

  private var currentProfile: Profile { profile ?? defaultProfile }

  private var defaultProfile: Profile {
    model.profiles.first { $0.vendorID == device.vendorID && $0.productID == device.productID }
      ?? Profile.makeDefault(
        for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      )
  }

  var body: some View {
    VStack(spacing: 0) {
      mappingList
      errorBanner
      Divider()
      resetBar
    }.onAppear { profile = defaultProfile }
  }

  private var mappingList: some View {
    List {
      mappingSection(title: "Face Buttons", buttons: [.a, .b, .x, .y])
      mappingSection(title: "Shoulders", buttons: [.leftBumper, .rightBumper])
      mappingSection(title: "System", buttons: [.start, .back, .guide])
      mappingSection(title: "D-Pad", buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight])
      axesSection
    }
  }

  @ViewBuilder private var errorBanner: some View {
    if let err = saveError { Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal) }
  }

  private var resetBar: some View {
    HStack {
      Spacer()
      SwiftUI.Button("Reset to Default", role: .destructive) { resetProfile() }.padding()
    }
  }

  private var axesSection: some View {
    Section("Axes") {
      deadzoneSlider
      mouseSensitivitySlider
      scrollSensitivitySlider
    }
  }

  private var deadzoneSlider: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Stick Deadzone: " + String(format: "%.2f", currentProfile.stickDeadzone))
      Slider(
        value: Binding(
          get: { Double(currentProfile.stickDeadzone) },
          set: { updateDeadzone(Float($0)) }
        ),
        in: 0...0.5
      )
    }
  }

  private var mouseSensitivitySlider: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Mouse Sensitivity: " + String(format: "%.1f", currentProfile.stickMouseSensitivity))
      Slider(
        value: Binding(
          get: { Double(currentProfile.stickMouseSensitivity) },
          set: { updateMouseSensitivity(Float($0)) }
        ),
        in: 1...20
      )
    }
  }

  private var scrollSensitivitySlider: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Scroll Sensitivity: " + String(format: "%.1f", currentProfile.stickScrollSensitivity))
      Slider(
        value: Binding(
          get: { Double(currentProfile.stickScrollSensitivity) },
          set: { updateScrollSensitivity(Float($0)) }
        ),
        in: 1...10
      )
    }
  }

  private func mappingSection(title: String, buttons: [OpenJoystickDriverKit.Button]) -> some View {
    Section(title) {
      ForEach(buttons, id: \.self) { button in
        KeyCaptureRow(
          label: button.displayName,
          keyCode: currentProfile.buttonMappings[button.rawValue] ?? 0
        ) { code in updateMapping(button: button, keyCode: code) }
      }
    }
  }

  private func updateMapping(button: OpenJoystickDriverKit.Button, keyCode: UInt16) {
    var updated = currentProfile
    updated.buttonMappings[button.rawValue] = keyCode
    profile = updated
    saveCurrentProfile(updated)
  }

  private func updateDeadzone(_ value: Float) {
    var updated = currentProfile
    updated.stickDeadzone = value
    profile = updated
    saveCurrentProfile(updated)
  }

  private func updateMouseSensitivity(_ value: Float) {
    var updated = currentProfile
    updated.stickMouseSensitivity = value
    profile = updated
    saveCurrentProfile(updated)
  }

  private func updateScrollSensitivity(_ value: Float) {
    var updated = currentProfile
    updated.stickScrollSensitivity = value
    profile = updated
    saveCurrentProfile(updated)
  }

  private func saveCurrentProfile(_ newProfile: Profile) {
    Task { @MainActor in
      do {
        try await model.saveProfile(newProfile)
        saveError = nil
      } catch { saveError = "Save failed: \(error.localizedDescription)" }
    }
  }

  private func resetProfile() {
    Task { @MainActor in
      do {
        try await model.resetProfile(vendorID: device.vendorID, productID: device.productID)
        profile = nil
        saveError = nil
      } catch { saveError = "Reset failed: \(error.localizedDescription)" }
    }
  }
}
