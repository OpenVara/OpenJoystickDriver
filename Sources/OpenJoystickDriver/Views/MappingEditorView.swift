import OpenJoystickDriverKit
import SwiftUI

private let xboxGreen = Color(red: 0.22, green: 0.71, blue: 0.29)
private let xboxRed = Color(red: 0.87, green: 0.20, blue: 0.20)
private let xboxBlue = Color(red: 0.0, green: 0.47, blue: 0.84)
private let xboxYellow = Color(red: 0.95, green: 0.77, blue: 0.06)

struct MappingEditorView: View {
  let device: DeviceViewModel
  @EnvironmentObject var model: AppModel
  @State private var profile: Profile?
  @State private var saveError: String?
  @State private var allProfiles: [Profile] = []
  @State private var creatingProfile = false
  @State private var newProfileName = ""
  @State private var profileError: String?
  @State private var showDeleteConfirm = false
  @State private var showResetConfirm = false

  private var currentProfile: Profile { profile ?? defaultProfile }

  private var defaultProfile: Profile {
    model.profiles.first { $0.vendorID == device.vendorID && $0.productID == device.productID }
      ?? Profile.makeDefault(
        for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      )
  }

  private var activeProfileID: UUID {
    allProfiles.first { profile?.id == $0.id }?.id ?? allProfiles.first?.id ?? UUID()
  }

  private var activeProfileBinding: Binding<UUID> {
    Binding(get: { activeProfileID }, set: { id in switchToProfile(id: id) })
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        profileCard
        if let err = profileError {
          Text(err).foregroundStyle(.orange).font(.caption).padding(.horizontal)
        }
        pairedMappingCard(
          title: "Face Buttons",
          systemImage: "circle.grid.2x2",
          buttons: [.a, .b, .x, .y]
        )
        pairedMappingCard(
          title: "Shoulders",
          systemImage: "l1.rectangle.roundedbottom",
          buttons: [.leftBumper, .rightBumper],
          labels: ["Left Shoulder", "Right Shoulder"]
        )
        triggersCard
        gridMappingCard(
          title: "System",
          systemImage: "ellipsis.circle",
          buttons: [.start, .back, .guide]
        )
        pairedMappingCard(
          title: "D-Pad",
          systemImage: "dpad",
          buttons: [.dpadUp, .dpadRight, .dpadLeft, .dpadDown],
          labels: ["Up", "Right", "Left", "Down"]
        )
        axesCard
      }.padding([.horizontal, .top]).padding(.bottom, 16)
    }.safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        errorBanner
        Divider()
        resetBar
      }.background(.bar)
    }.onAppear {
      profile = defaultProfile
      loadAllProfiles()
    }
  }

  private var profileCard: some View {
    GroupBox {
      if creatingProfile {
        HStack {
          TextField("Profile name...", text: $newProfileName).textFieldStyle(.roundedBorder)
          SwiftUI.Button("Save") { saveNewProfile() }.disabled(
            newProfileName.trimmingCharacters(in: .whitespaces).isEmpty
          )
          SwiftUI.Button("Cancel") {
            creatingProfile = false
            newProfileName = ""
          }
        }
      } else {
        HStack {
          Picker("Profile", selection: activeProfileBinding) {
            ForEach(allProfiles, id: \.id) { p in Text(p.name).tag(p.id) }
          }.pickerStyle(.menu).labelsHidden()
          Spacer()
          SwiftUI.Button {
            newProfileName = ""
            creatingProfile = true
          } label: {
            Label("New", systemImage: "plus")
          }
          SwiftUI.Button("Delete", role: .destructive) { showDeleteConfirm = true }.disabled(
            allProfiles.count <= 1
          )
        }
      }
    } label: {
      Label("Profile", systemImage: "doc.badge.gearshape").fontWeight(.semibold)
    }.confirmationDialog("Delete Profile?", isPresented: $showDeleteConfirm) {
      SwiftUI.Button("Delete", role: .destructive) { deleteCurrentProfile() }
      SwiftUI.Button("Cancel", role: .cancel) {}
    } message: {
      Text("This profile will be permanently removed.")
    }
  }

  private func buttonBadge(for button: OpenJoystickDriverKit.Button) -> ButtonBadge? {
    if device.parser.uppercased() == "GIP" {
      switch button {
      case .a: return .xboxFace("A", xboxGreen)
      case .b: return .xboxFace("B", xboxRed)
      case .x: return .xboxFace("X", xboxBlue)
      case .y: return .xboxFace("Y", xboxYellow)
      case .guide: return .xboxLogo
      default: break
      }
    }
    switch button {
    case .dpadUp: return .sfSymbol("arrow.up")
    case .dpadDown: return .sfSymbol("arrow.down")
    case .dpadLeft: return .sfSymbol("arrow.left")
    case .dpadRight: return .sfSymbol("arrow.right")
    case .leftBumper: return .sfSymbol("l1.rectangle.roundedbottom")
    case .rightBumper: return .sfSymbol("r1.rectangle.roundedbottom")
    case .start: return .sfSymbol("line.3.horizontal")
    case .back: return .sfSymbol("square.on.square")
    case .guide: return .sfSymbol("house.circle")
    case .share: return .sfSymbol("square.and.arrow.up")
    default: return nil
    }
  }

  private func buttonTooltip(for button: OpenJoystickDriverKit.Button) -> String {
    switch button {
    case .a: return "A — confirm / accept"
    case .b: return "B — cancel / back"
    case .x: return "X — secondary action"
    case .y: return "Y — secondary action"
    case .guide: return "Guide / Home — opens the system overlay"
    case .start: return "Menu / Start — opens the in-game pause menu"
    case .back: return "View / Back — toggles secondary view or minimap"
    case .leftBumper: return "LB — Left Bumper (upper shoulder button)"
    case .rightBumper: return "RB — Right Bumper (upper shoulder button)"
    case .dpadUp: return "D-Pad Up"
    case .dpadDown: return "D-Pad Down"
    case .dpadLeft: return "D-Pad Left"
    case .dpadRight: return "D-Pad Right"
    default: return button.displayName
    }
  }

  /// Vertical list of single-column rows.
  private func gridMappingCard(
    title: String,
    systemImage: String,
    buttons: [OpenJoystickDriverKit.Button],
    labels: [String]? = nil
  ) -> some View {
    GroupBox {
      VStack(spacing: 0) {
        ForEach(Array(buttons.enumerated()), id: \.element) { idx, button in
          if idx > 0 { Divider() }
          KeyCaptureRow(
            label: labels?[idx] ?? button.displayName,
            keyCode: currentProfile.buttonMappings[button.rawValue] ?? 0,
            badge: buttonBadge(for: button)
          ) { code in updateMapping(button: button, keyCode: code) }.padding(.vertical, 2).help(
            buttonTooltip(for: button)
          )
        }
      }
    } label: {
      Label(title, systemImage: systemImage).fontWeight(.semibold)
    }
  }

  /// Renders buttons in side-by-side pairs (2 per row), matching the
  /// physical layout of controller button groups.
  private func pairedMappingCard(
    title: String,
    systemImage: String,
    buttons: [OpenJoystickDriverKit.Button],
    labels: [String]? = nil
  ) -> some View {
    let rows: [[OpenJoystickDriverKit.Button]] = stride(from: 0, to: buttons.count, by: 2).map {
      Array(buttons[$0..<min($0 + 2, buttons.count)])
    }
    return GroupBox {
      VStack(spacing: 0) {
        ForEach(rows.indices, id: \.self) { rowIdx in
          if rowIdx > 0 { Divider() }
          pairRow(
            left: rows[rowIdx][0],
            right: rows[rowIdx].count > 1 ? rows[rowIdx][1] : nil,
            labels: labels,
            baseIdx: rowIdx * 2
          )
        }
      }
    } label: {
      Label(title, systemImage: systemImage).fontWeight(.semibold)
    }
  }

  private func pairRow(
    left: OpenJoystickDriverKit.Button,
    right: OpenJoystickDriverKit.Button?,
    labels: [String]?,
    baseIdx: Int
  ) -> some View {
    HStack(spacing: 0) {
      KeyCaptureRow(
        label: labels?[baseIdx] ?? left.displayName,
        keyCode: currentProfile.buttonMappings[left.rawValue] ?? 0,
        badge: buttonBadge(for: left)
      ) { code in updateMapping(button: left, keyCode: code) }.padding(.vertical, 2).help(
        buttonTooltip(for: left)
      )
      if let right {
        Divider().padding(.horizontal, 6)
        KeyCaptureRow(
          label: labels?[baseIdx + 1] ?? right.displayName,
          keyCode: currentProfile.buttonMappings[right.rawValue] ?? 0,
          badge: buttonBadge(for: right)
        ) { code in updateMapping(button: right, keyCode: code) }.padding(.vertical, 2).help(
          buttonTooltip(for: right)
        )
      } else {
        Spacer()
      }
    }
  }

  private var triggersCard: some View {
    GroupBox {
      HStack(spacing: 0) {
        KeyCaptureRow(
          label: "Left Trigger",
          keyCode: currentProfile.buttonMappings["leftTrigger"] ?? 0,
          badge: .textLabel("LT")
        ) { code in updateTriggerMapping(key: "leftTrigger", keyCode: code) }.padding(.vertical, 2)
          .help("LT — Left Trigger. Assign a key to fire on full press.")
        Divider().padding(.horizontal, 6)
        KeyCaptureRow(
          label: "Right Trigger",
          keyCode: currentProfile.buttonMappings["rightTrigger"] ?? 0,
          badge: .textLabel("RT")
        ) { code in updateTriggerMapping(key: "rightTrigger", keyCode: code) }.padding(.vertical, 2)
          .help("RT — Right Trigger. Assign a key to fire on full press.")
      }
    } label: {
      Label("Triggers", systemImage: "arrow.down.circle").fontWeight(.semibold)
    }
  }

  private var axesCard: some View {
    GroupBox {
      VStack(spacing: 0) {
        deadzoneSlider.help(
          "Deadzone: minimum stick deflection before input registers."
            + " Raise if small resting movements cause unintended actions."
        )
        Divider()
        mouseSensitivitySlider.help("How fast the left stick moves the mouse cursor.")
        Divider()
        scrollSensitivitySlider.help("How fast the right stick scrolls.")
      }
    } label: {
      Label("Axes", systemImage: "dial.medium").fontWeight(.semibold)
    }
  }

  @ViewBuilder private var errorBanner: some View {
    if let err = saveError { Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal) }
  }

  private var resetBar: some View {
    HStack {
      Spacer()
      SwiftUI.Button("Reset to Default", role: .destructive) { showResetConfirm = true }.padding()
    }.confirmationDialog("Reset to Default?", isPresented: $showResetConfirm) {
      SwiftUI.Button("Reset", role: .destructive) { resetProfile() }
      SwiftUI.Button("Cancel", role: .cancel) {}
    } message: {
      Text("All mappings will be restored to their defaults.")
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
    }.padding(.vertical, 4)
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
    }.padding(.vertical, 4)
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
    }.padding(.vertical, 4)
  }

  private func loadAllProfiles() {
    Task { @MainActor in
      do {
        allProfiles = try await model.allProfiles(
          vendorID: device.vendorID,
          productID: device.productID
        )
        if let active = allProfiles.first(where: { $0.id == profile?.id }) {
          profile = active
        } else if let first = allProfiles.first {
          profile = first
        }
        profileError = nil
      } catch {
        // Daemon unreachable — show current profile only, no alarming error
        if allProfiles.isEmpty { allProfiles = [currentProfile] }
        if model.daemonConnected { profileError = "Profile sync failed — changes may not persist." }
      }
    }
  }

  private func switchToProfile(id: UUID) {
    Task { @MainActor in
      do {
        try await model.setActiveProfile(
          id: id,
          vendorID: device.vendorID,
          productID: device.productID
        )
        await model.refreshProfiles()
        allProfiles = try await model.allProfiles(
          vendorID: device.vendorID,
          productID: device.productID
        )
        if let active = allProfiles.first(where: { $0.id == id }) { profile = active }
        profileError = nil
      } catch { profileError = "Switch failed: \(error.localizedDescription)" }
    }
  }

  private func saveNewProfile() {
    let name = newProfileName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    Task { @MainActor in
      do {
        let newProfile = try await model.addProfile(name: name, basedOn: currentProfile)
        try await model.setActiveProfile(
          id: newProfile.id,
          vendorID: device.vendorID,
          productID: device.productID
        )
        await model.refreshProfiles()
        allProfiles = try await model.allProfiles(
          vendorID: device.vendorID,
          productID: device.productID
        )
        if let active = allProfiles.first(where: { $0.id == newProfile.id }) { profile = active }
        creatingProfile = false
        newProfileName = ""
        profileError = nil
      } catch { profileError = "Create failed: \(error.localizedDescription)" }
    }
  }

  private func deleteCurrentProfile() {
    Task { @MainActor in
      do {
        try await model.deleteProfile(
          id: currentProfile.id,
          vendorID: device.vendorID,
          productID: device.productID
        )
        await model.refreshProfiles()
        allProfiles = try await model.allProfiles(
          vendorID: device.vendorID,
          productID: device.productID
        )
        profile = allProfiles.first
        profileError = nil
      } catch { profileError = "Delete failed: \(error.localizedDescription)" }
    }
  }

  private func updateMapping(button: OpenJoystickDriverKit.Button, keyCode: UInt16) {
    var updated = currentProfile
    updated.buttonMappings[button.rawValue] = keyCode
    profile = updated
    saveCurrentProfile(updated)
  }

  private func updateTriggerMapping(key: String, keyCode: UInt16) {
    var updated = currentProfile
    if keyCode == 0 {
      updated.buttonMappings.removeValue(forKey: key)
    } else {
      updated.buttonMappings[key] = keyCode
    }
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
