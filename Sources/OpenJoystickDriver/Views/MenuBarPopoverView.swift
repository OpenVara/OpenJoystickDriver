import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State private var runningSelfTest = false
  @State private var showUninstallConfirm = false
  @State private var showAdvanced = false
  @State private var inputTester = InputTestWindowController()

  private var gameControllerSupportLabel: String {
    guard let devices = model.virtualDeviceDiagnostics?.hidGamepads else {
      return "unknown"
    }
    let ojdDevices = devices.filter { $0.isOJDUserSpace || $0.isOJDDriverKit }
    if ojdDevices.isEmpty { return "no OJD virtual device visible" }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == true }) {
      return "yes"
    }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == nil }) {
      return "unknown on this macOS version"
    }
    return "no"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        headerRow
        readinessCard
        permissionsCard
        gameProfileCard
        inputTestRow
        advancedToggle
        if showAdvanced {
          outputDetailsCard
          helperCard
          selfTestRow
          updateRow
          footerRow
        }
      }
      .padding(14)
    }
    .frame(width: 440)
    .onAppear {
      Task {
        await model.syncFromDaemonNow()
        model.extensionManager.refreshInstallState()
      }
    }
    .alert(isPresented: $showUninstallConfirm) {
      Alert(
        title: Text("Uninstall LaunchAgent?"),
        message: Text("This removes the LaunchAgent plist. You can reinstall later."),
        primaryButton: .destructive(Text("Uninstall")) {
          Task {
            await model.uninstallDaemon()
            await model.syncFromDaemonNow()
          }
        },
        secondaryButton: .cancel()
      )
    }
  }

  private var headerRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("OpenJoystickDriver")
          .font(.system(size: 17, weight: .semibold))
      }
      Spacer()
      SwiftUI.Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)
        .foregroundColor(.secondary)
    }
  }

  private var readinessCard: some View {
    let daemonStatusLabel =
      model.daemonRestarting
      ? "restarting..."
      : (model.daemonConnected ? "running" : (model.daemonInstalled ? "installed" : "missing"))
    let permissionsReady =
      model.appInputMonitoring == "granted" && model.inputMonitoring == "granted"
    let ready = model.daemonConnected && permissionsReady
    let title = ready ? "Ready for games" : "Setup needs attention"
    let summary: String = {
      if model.daemonRestarting { return "The helper is restarting." }
      if !model.daemonInstalled { return "Install the helper to read controller input." }
      if !model.daemonConnected { return "Start the helper to connect controllers." }
      if model.appInputMonitoring != "granted" { return "Grant Input Monitoring for OpenJoystickDriver." }
      if model.inputMonitoring != "granted" { return "Grant Input Monitoring for OpenJoystickDriver Helper." }
      if model.devices.isEmpty { return "Connect a controller to start playing." }
      return "\(model.devices.count) controller\(model.devices.count == 1 ? "" : "s") connected."
    }()

    return OJDCard {
      HStack(alignment: .top, spacing: 12) {
        StatusOrb(isReady: ready, isBusy: model.daemonRestarting)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Text(daemonStatusLabel)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .foregroundColor(ready ? .green : .secondary)
          .background(Capsule().fill(Color.secondary.opacity(0.12)))
      }

      HStack(spacing: 10) {
        MetricChip(title: "Controllers", value: "\(model.devices.count)")
        MetricChip(title: "Profile", value: compatibilityIdentityLabel)
        MetricChip(title: "Access", value: permissionsReady ? "Allowed" : "Needs access")
      }
      .padding(.top, 4)

      if !ready {
        readinessAction
      }

      if let err = model.daemonError {
        Text(err)
          .font(.caption)
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }
    }
  }

  @ViewBuilder
  private var readinessAction: some View {
    if model.daemonRestarting {
      EmptyView()
    } else if !model.daemonInstalled {
      SwiftUI.Button("Install Helper") {
        Task {
          await model.installDaemon()
          await model.syncFromDaemonNow()
        }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.daemonConnected {
      SwiftUI.Button("Start Helper") {
        Task {
          await model.startDaemon()
          await model.syncFromDaemonNow()
        }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if model.appInputMonitoring != "granted" {
      SwiftUI.Button("Ask macOS") {
        Task { await model.requestAppInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if model.inputMonitoring != "granted" {
      SwiftUI.Button("Ask macOS") {
        Task { await model.requestDaemonInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    }
  }

  private var helperCard: some View {
    OJDCard(title: "Helper") {
      VStack(alignment: .leading, spacing: 10) {
        if let h = model.daemonHealth, h.installed {
          let state = h.state ?? "unknown"
          let pid = h.pid.map { "\($0)" } ?? "?"
          let runs = h.runs.map { "\($0)" } ?? "?"
          let reason = h.isInefficientKillLoop ? (h.immediateReason ?? h.blame) : nil
          HStack(spacing: 8) {
            Text("launchd \(state), pid \(pid), runs \(runs)\(reason.map { ", \($0)" } ?? "")")
              .font(.caption)
              .foregroundColor(h.isInefficientKillLoop ? .orange : .secondary)
              .lineLimit(2)
            Spacer()
            SwiftUI.Button("Refresh") {
              Task { await model.refreshDaemonHealth() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }
        } else {
          Text("The helper starts automatically after install.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Text("System extension")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(model.extensionManager.installState.label)
            .font(.caption.weight(.semibold))
            .foregroundColor(model.extensionManager.installState.isInstalled ? .green : .secondary)
          SwiftUI.Button("Install") { model.extensionManager.installExtension() }
            .controlSize(.small)
            .disabled(
              model.extensionManager.installState.isInstalled ||
                model.extensionManager.installState.isPending
            )
        }
        if case .failed(let msg) = model.extensionManager.installState {
          Text(msg)
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let warning = model.extensionManager.installWarning, model.extensionManager.installState.isInstalled {
          Text(warning)
            .font(.caption)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 8) {
          if !model.daemonInstalled {
            SwiftUI.Button("Install Helper") {
              Task {
                await model.installDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
          } else {
            SwiftUI.Button("Start") {
              Task {
                await model.startDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
            .disabled(model.daemonConnected)
            SwiftUI.Button("Restart") {
              Task {
                await model.restartDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
            .disabled(model.daemonRestarting)
            SwiftUI.Button("Uninstall") { showUninstallConfirm = true }
              .buttonStyle(.borderless)
              .controlSize(.small)
              .foregroundColor(.secondary)
              .disabled(model.daemonRestarting)
          }
        }
      }
    }
  }

  private var permissionsCard: some View {
    OJDCard(title: "Permissions") {
      VStack(alignment: .leading, spacing: 8) {
        PermissionRow(
          title: "OpenJoystickDriver",
          subtitle: permissionSubtitle(for: model.appInputMonitoring, owner: "the app"),
          state: model.appInputMonitoring,
          actionTitle: permissionActionTitle(for: model.appInputMonitoring)
        ) {
          Task { await model.requestAppInputMonitoringAccess() }
        }
        Divider()
        PermissionRow(
          title: "OpenJoystickDriver Helper",
          subtitle: permissionSubtitle(
            for: model.inputMonitoring,
            owner: "the helper",
            settingsName: "OpenJoystickDriver Helper"
          ),
          state: model.inputMonitoring,
          actionTitle: permissionActionTitle(for: model.inputMonitoring),
          disabled: !model.daemonConnected
        ) {
          Task { await model.requestDaemonInputMonitoringAccess() }
        }
        if let assist = model.inputMonitoringAssist {
          PermissionAssistView(message: assist)
        }
      }
    }
  }

  private func permissionActionTitle(for state: String) -> String {
    state == "granted" ? "Allowed" : "Ask macOS"
  }

  private func permissionSubtitle(
    for state: String,
    owner: String,
    settingsName: String? = nil
  ) -> String {
    switch state {
    case "granted":
      return "Ready."
    case "denied":
      let name = settingsName ?? owner
      return "Open System Settings and turn on Input Monitoring for \(name)."
    default:
      return "Ask macOS to add this item to Input Monitoring."
    }
  }

  private var gameProfileCard: some View {
    OJDCard(title: "Games") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Choose the game profile.")
              .font(.caption.weight(.semibold))
            Text("Compatibility works best for Steam, emulators, and most games.")
              .font(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if model.virtualDeviceMode != VirtualDeviceMode.compatUserSpace.rawValue {
            SwiftUI.Button("Use for Games") {
              Task { await model.setVirtualDeviceMode(VirtualDeviceMode.compatUserSpace.rawValue) }
            }
            .controlSize(.small)
            .disabled(!model.daemonConnected)
          }
        }

        let compatSelected = model.virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
        HStack(spacing: 10) {
          Text("Profile")
            .font(.caption)
            .foregroundColor(.secondary)
          Picker(
            "Game profile",
            selection: Binding(
              get: { model.compatibilityIdentity },
              set: { v in Task { await model.setCompatibilityIdentity(v) } }
            )
          ) {
            Text("SDL 2/3").tag(CompatibilityIdentity.sdl2_3.rawValue)
            Text("Apple GameController").tag(CompatibilityIdentity.appleGameController.rawValue)
            Text("Generic HID").tag(CompatibilityIdentity.genericHID.rawValue)
            Text("Xbox 360 HID").tag(CompatibilityIdentity.x360HID.rawValue)
            Text("Xbox One HID").tag(CompatibilityIdentity.xoneHID.rawValue)
          }
          .frame(maxWidth: .infinity)
          .disabled(!model.daemonConnected || !compatSelected)
        }

        if !compatSelected {
          Text("Switch to game mode before changing profiles.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var outputDetailsCard: some View {
    OJDCard(title: "Output details") {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          "Mode",
          selection: Binding(
            get: { model.virtualDeviceMode },
            set: { newValue in Task { await model.setVirtualDeviceMode(newValue) } }
          )
        ) {
          Text("Auto").tag(VirtualDeviceMode.auto.rawValue)
          Text("DriverKit").tag(VirtualDeviceMode.driverKit.rawValue)
          Text("Compatibility").tag(VirtualDeviceMode.compatUserSpace.rawValue)
          if model.developerMode {
            Text("Both").tag(VirtualDeviceMode.both.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .disabled(!model.daemonConnected)

        VStack(alignment: .leading, spacing: 3) {
          statusLine("Active", activeOutputLabel)
          statusLine("Backend", model.userSpaceVirtualDeviceStatus, warning: model.userSpaceVirtualDeviceStatus.hasPrefix("error:"))
          statusLine("GameController", gameControllerSupportLabel, success: gameControllerSupportLabel == "yes")
          if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
            statusLine("DriverKit reports", "ok \(s.successes), fail \(s.failures), last \(s.lastErrorHex ?? "none")")
          }
        }
      }
    }
  }

  private func statusLine(_ label: String, _ value: String, success: Bool = false, warning: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 96, alignment: .leading)
      Text(value)
        .font(.caption)
        .foregroundColor(success ? .green : (warning ? .orange : .secondary))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var activeOutputLabel: String {
    switch model.outputMode {
    case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return "DriverKit"
    case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue: return "Compatibility"
    case CompositeOutputDispatcher.Mode.both.rawValue: return "Both"
    default: return "Unknown"
    }
  }

  private var compatibilityIdentityLabel: String {
    switch model.compatibilityIdentity {
    case CompatibilityIdentity.sdl2_3.rawValue: return "SDL"
    case CompatibilityIdentity.appleGameController.rawValue: return "GameController"
    case CompatibilityIdentity.genericHID.rawValue: return "Generic HID"
    case CompatibilityIdentity.x360HID.rawValue: return "Xbox 360"
    case CompatibilityIdentity.xoneHID.rawValue: return "Xbox One"
    default: return model.compatibilityIdentity
    }
  }

  private var selfTestRow: some View {
    OJDCard(title: "Self-test") {
      VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Verify virtual output for five seconds.")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        SwiftUI.Button(runningSelfTest ? "Running…" : "Run 5s") {
          runningSelfTest = true
          Task {
            await model.syncFromDaemonNow()
            if model.daemonHealth?.isInefficientKillLoop == true {
              model.daemonError =
                "Daemon is being killed by launchd (inefficient). Fix daemon stability before self-test."
              runningSelfTest = false
              return
            }
            await model.runVirtualDeviceSelfTest(seconds: 5)
            runningSelfTest = false
          }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!model.daemonConnected || runningSelfTest)
      }
      if let t = model.virtualDeviceSelfTest {
        VStack(alignment: .leading, spacing: 3) {
          statusLine("DriverKit", "value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)")
          if let delta = t.driverKitInputReportDelta {
            statusLine("ioreg input", "Δ \(delta)")
          }
          if let delta = t.driverKitSetReportSuccessDelta {
            statusLine("daemon setReport", "ok Δ \(delta)")
          }
          statusLine("User-space", "value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)")
        }
      } else {
        Text("Press buttons while it runs.").font(.caption).foregroundColor(.secondary)
      }
      }
    }
  }

  private var inputTestRow: some View {
    OJDCard(title: "Input test") {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Live buttons, sticks, packet log, and rumble.")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button("Open Input Test") {
            inputTester.show(model: model)
          }
          .controlSize(.small)
          .disabled(!model.daemonConnected)
        }
      }
    }
  }

  private var advancedToggle: some View {
    SwiftUI.Button {
      showAdvanced.toggle()
    } label: {
      HStack {
        Text(showAdvanced ? "Hide details" : "Show details")
        Spacer()
        Text(showAdvanced ? "▴" : "▾")
      }
      .font(.caption.weight(.semibold))
      .foregroundColor(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.secondary.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
  }

  private var footerRow: some View {
    HStack(spacing: 10) {
      SwiftUI.Button("Refresh") {
        Task {
          await model.syncFromDaemonNow()
        }
      }
      .buttonStyle(.borderless)

      SwiftUI.Button("Show Log") {
        NSWorkspace.shared.selectFile("/tmp/com.openjoystickdriver.daemon.out", inFileViewerRootedAtPath: "")
      }
      .buttonStyle(.borderless)

      SwiftUI.Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)

      Spacer()
    }
    .font(.caption)
  }

  private var updateRow: some View {
    OJDCard(title: "Updates") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(updateStatusLine)
            .font(.caption)
            .foregroundColor(updateStatusColor)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          SwiftUI.Button(updateButtonTitle) {
            Task { await model.checkForUpdates() }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(model.updateCheckState == .checking)
        }

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text("OpenJoystickDriver \(info.tagName) is available.")
              .font(.caption)
              .foregroundColor(.orange)
            Spacer()
            SwiftUI.Button("Open") { model.openLatestRelease() }
              .buttonStyle(.borderless)
              .controlSize(.small)
          }
        }
      }
    }
  }

  private var updateButtonTitle: String {
    model.updateCheckState == .checking ? "Checking…" : "Check"
  }

  private var updateStatusLine: String {
    switch model.updateCheckState {
    case .idle: return "Current version \(model.appVersion)."
    case .checking: return "Checking GitHub releases…"
    case .upToDate(let version): return "OpenJoystickDriver \(version) is current."
    case .available: return "A newer release is ready."
    case .failed(let message): return "Update check failed: \(message)"
    }
  }

  private var updateStatusColor: Color {
    switch model.updateCheckState {
    case .upToDate: return .green
    case .available, .failed: return .orange
    default: return .secondary
    }
  }
}

private struct OJDCard<Content: View>: View {
  private let title: String?
  private let content: Content

  init(title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.secondary)
      }
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(NSColor.controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
    )
  }
}

private struct StatusOrb: View {
  let isReady: Bool
  let isBusy: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill((isReady ? Color.green : (isBusy ? Color.orange : Color.secondary)).opacity(0.14))
      Circle()
        .fill(isReady ? Color.green : (isBusy ? Color.orange : Color.secondary))
        .frame(width: 10, height: 10)
    }
    .frame(width: 28, height: 28)
  }
}

private struct MetricChip: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
      Text(value)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}

private struct PermissionRow: View {
  let title: String
  let subtitle: String
  let state: String
  let actionTitle: String
  var disabled = false
  let action: () -> Void

  private var isGranted: Bool { state == "granted" }
  private var isDenied: Bool { state == "denied" }
  private var symbol: String {
    if isGranted { return "✓" }
    if isDenied { return "!" }
    return "…"
  }
  private var statusLabel: String {
    switch state {
    case "granted": return "Allowed"
    case "denied": return "Needs approval"
    default: return "Not set up"
    }
  }
  private var statusColor: Color {
    if isGranted { return .green }
    if isDenied { return .orange }
    return .secondary
  }

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Text(symbol)
        .font(.caption.weight(.bold))
        .foregroundColor(statusColor)
        .frame(width: 22, height: 22)
        .background(Circle().fill(statusColor.opacity(0.12)))

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(title)
            .font(.caption.weight(.semibold))
          Text(statusLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
        }
        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      SwiftUI.Button(actionTitle, action: action)
        .controlSize(.small)
        .disabled(disabled || isGranted)
    }
  }
}

private struct PermissionAssistView: View {
  let message: String

  var body: some View {
    Text(message)
      .font(.caption)
      .foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.secondary.opacity(0.08))
      )
  }
}

private struct MiniBadge: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.system(size: 10, weight: .semibold))
      .foregroundColor(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color.secondary.opacity(0.10)))
  }
}

@MainActor private final class InputTestWindowController {
  private let compactSize = NSSize(width: 860, height: 560)
  private var window: NSWindow?

  func show(model: AppModel) {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let root = InputTestWindowView().environmentObject(model)
    let hosting = NSHostingController(rootView: root)
    let newWindow = NSWindow(contentViewController: hosting)
    newWindow.title = "OpenJoystickDriver Input Test"
    newWindow.setContentSize(compactSize)
    newWindow.minSize = compactSize
    newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    newWindow.isReleasedWhenClosed = false
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = newWindow
  }
}

private actor InputTestSampler {
  private let client = XPCClient()

  init() {
    client.connect()
  }

  func disconnect() {
    client.disconnect()
  }

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }
}

private struct InputTestWindowView: View {
  private let inputRefreshIntervalNanoseconds: UInt64 = 8_333_333
  private let packetLogRefreshIntervalNanoseconds: UInt64 = 1_000_000_000

  @EnvironmentObject var model: AppModel
  @State private var selectedDeviceID: String?
  @State private var state: DeviceInputState?
  @State private var packetLog: [PacketLogEntry] = []
  @State private var rumbleRunning = false
  @State private var rumbleResult: String?
  @State private var rumbleLeft = 180.0
  @State private var rumbleRight = 180.0
  @State private var rumbleLT = 0.0
  @State private var rumbleRT = 0.0
  @State private var rumbleDurationMs = 450.0
  @State private var showPackets = false
  @State private var stateTask: Task<Void, Never>?
  @State private var packetLogTask: Task<Void, Never>?
  @State private var sampler = InputTestSampler()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let device = selectedDevice {
          VStack(alignment: .leading, spacing: 14) {
            controllerHero(device)
            HStack(alignment: .top, spacing: 16) {
              OJDCard(title: "Live input") {
                axesGrid
                Divider()
                buttonGrid
              }
              .frame(width: 350, alignment: .topLeading)

              VStack(alignment: .leading, spacing: 12) {
                outputTestRow(device)
                packetLogToggle
                if showPackets {
                  packetLogView
                }
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
          }
        } else {
          OJDCard {
            VStack(spacing: 10) {
              StatusOrb(isReady: false, isBusy: false)
              Text("No controller selected").font(.headline)
              Text("Connect a controller or restart the helper, then refresh.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
          }
        }
      }
      .padding(18)
    }
    .frame(minWidth: 860, minHeight: 560)
    .onAppear {
      selectedDeviceID = selectedDeviceID ?? model.devices.first?.id
      startRefreshTasks()
    }
    .onDisappear {
      stateTask?.cancel()
      packetLogTask?.cancel()
      stateTask = nil
      packetLogTask = nil
      Task { await sampler.disconnect() }
    }
  }

  private var selectedDevice: DeviceViewModel? {
    if let selectedDeviceID, let selected = model.devices.first(where: { $0.id == selectedDeviceID }) {
      return selected
    }
    return model.devices.first
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Input Test")
          .font(.system(size: 24, weight: .semibold))
        Text("Live controller input and feedback checks.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      HStack(spacing: 8) {
        Text("Controller")
          .font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
        Picker("", selection: Binding(get: {
          selectedDevice?.id ?? ""
        }, set: { value in
          selectedDeviceID = value
        })) {
          ForEach(model.devices) { device in
            Text(device.name).tag(device.id)
          }
        }
        .labelsHidden()
        .frame(width: 260)
        .disabled(model.devices.isEmpty)
        SwiftUI.Button("Refresh") {
          Task {
            await model.syncFromDaemonNow()
            await refreshState()
            await refreshPacketLog()
          }
        }
        .controlSize(.small)
      }
    }
  }

  private func controllerHero(_ device: DeviceViewModel) -> some View {
    OJDCard {
      HStack(alignment: .center, spacing: 14) {
        StatusOrb(isReady: state != nil, isBusy: false)
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Text(device.name)
              .font(.system(size: 19, weight: .semibold))
              .lineLimit(1)
            Text(state == nil ? "idle" : "live")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(state == nil ? .secondary : .green)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Capsule().fill((state == nil ? Color.secondary : Color.green).opacity(0.12)))
          }
          HStack(spacing: 7) {
            MiniBadge(device.parser)
            MiniBadge(device.connection)
            MiniBadge(String(format: "%04X:%04X", device.vendorID, device.productID))
            if let serial = device.serialNumber, !serial.isEmpty {
              MiniBadge("Serial \(serial)")
                .layoutPriority(-1)
            }
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(state == nil ? "Move any control" : "Input received")
            .font(.caption.weight(.semibold))
          Text(buttonSummary)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private var axesGrid: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Sticks and triggers").font(.caption.weight(.semibold))
        Spacer()
        Text(state == nil ? "idle" : "live")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(state == nil ? .secondary : .green)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "Left X", value: state?.leftStickX ?? 0, range: -1...1)
        AxisMeter(label: "Left Y", value: state?.leftStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "Right X", value: state?.rightStickX ?? 0, range: -1...1)
        AxisMeter(label: "Right Y", value: state?.rightStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "LT", value: state?.leftTrigger ?? 0, range: 0...1)
        AxisMeter(label: "RT", value: state?.rightTrigger ?? 0, range: 0...1)
      }
    }
  }

  private var buttonGrid: some View {
    let pressed = Set(state?.pressedButtons ?? [])
    let buttons = supportedButtons(for: selectedDevice?.parser)
    let columnCount = 6
    let rowCount = (buttons.count + columnCount - 1) / columnCount
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Buttons").font(.caption.weight(.semibold))
        Spacer()
        Text(pressed.isEmpty ? "none pressed" : "\(pressed.count) pressed")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(pressed.isEmpty ? .secondary : .accentColor)
      }
      VStack(alignment: .leading, spacing: 6) {
        ForEach(0..<rowCount, id: \.self) { row in
          HStack(spacing: 6) {
            ForEach(0..<columnCount, id: \.self) { column in
              let index = row * columnCount + column
              if index < buttons.count {
                let button = buttons[index]
                buttonPill(button: button, isDown: pressed.contains(button.rawValue))
              }
            }
          }
        }
      }
    }
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  private var buttonSummary: String {
    let pressed = state?.pressedButtons ?? []
    if pressed.isEmpty {
      return "No buttons pressed"
    }
    return "\(pressed.count) button\(pressed.count == 1 ? "" : "s") pressed"
  }

  @ViewBuilder
  private func buttonPill(button: OpenJoystickDriverKit.Button, isDown: Bool) -> some View {
    if #available(macOS 11.0, *) {
      Image(systemName: button.systemImageName)
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 32, height: 30)
        .background(isDown ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.14))
        .foregroundColor(isDown ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transaction { transaction in
          transaction.animation = nil
        }
        .accessibilityLabel(Text(button.displayName))
    } else {
      Text(button.displayName)
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: 32, height: 30)
        .background(isDown ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.14))
        .foregroundColor(isDown ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transaction { transaction in
          transaction.animation = nil
        }
    }
  }

  private func supportedButtons(for parser: String?) -> [OpenJoystickDriverKit.Button] {
    switch parser {
    case "DS4":
      return [
        .cross, .circle, .square, .triangle,
        .l1, .r1, .leftStick, .rightStick,
        .share, .options, .ps, .touchpad,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    case "GIP":
      return [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper,
        .leftStick, .rightStick,
        .back, .start, .guide, .share,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    case "Xbox360":
      return [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper,
        .leftStick, .rightStick,
        .back, .start, .guide,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    default:
      return [
        .genericButton1, .genericButton2, .genericButton3, .genericButton4,
        .genericButton5, .genericButton6, .genericButton7, .genericButton8,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    }
  }

  private func outputTestRow(_ device: DeviceViewModel) -> some View {
    let canRumble = device.supportsPhysicalRumble
    return OJDCard(title: "Rumble test") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(canRumble ? "Send a short pulse to confirm feedback." : "This controller does not expose rumble.")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(canRumble ? "supported" : "unavailable")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(canRumble ? .green : .secondary)
        }
        VStack(alignment: .leading, spacing: 7) {
          Text("Motors")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: "Left", value: $rumbleLeft)
              RumbleSlider(label: "Right", value: $rumbleRight)
            }
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: "LT", value: $rumbleLT)
              RumbleSlider(label: "RT", value: $rumbleRT)
            }
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            rumbleIconButton(
              rumbleRunning ? "Sending" : "Pulse",
              systemName: rumbleRunning ? "hourglass" : "waveform.path.ecg"
            ) {
              sendRumble(to: device, durationMs: Int(rumbleDurationMs))
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton("Hold", systemName: "infinity") {
              sendRumble(to: device, durationMs: 0)
            }
            .disabled(!canRumble)
            rumbleIconButton("Stop", systemName: "stop.fill") {
              sendRumble(to: device, left: 0, right: 0, lt: 0, rt: 0, durationMs: 0)
            }
            .disabled(!canRumble)
            Divider().frame(height: 18)
            Stepper("Duration \(Int(rumbleDurationMs)) ms", value: $rumbleDurationMs, in: 50...5000, step: 50)
              .font(.caption)
              .frame(width: 160)
          }
          HStack(spacing: 8) {
            rumbleIconButton("Left motor", systemName: "l.circle") {
              sendRumble(to: device, left: UInt8(clamping: Int(rumbleLeft)), right: 0, lt: 0, rt: 0)
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton("Right motor", systemName: "r.circle") {
              sendRumble(to: device, left: 0, right: UInt8(clamping: Int(rumbleRight)), lt: 0, rt: 0)
            }
            .disabled(rumbleRunning || !canRumble)
            Divider().frame(height: 16)
            rumbleIconButton("Low", systemName: "speaker.wave.1.fill") {
              setRumbleValues(left: 32, right: 32, lt: 32, rt: 32)
            }
            rumbleIconButton("Mid", systemName: "speaker.wave.2.fill") {
              setRumbleValues(left: 128, right: 128, lt: 128, rt: 128)
            }
            rumbleIconButton("Max", systemName: "speaker.wave.3.fill") {
              setRumbleValues(left: 255, right: 255, lt: 255, rt: 255)
            }
            rumbleIconButton("Zero", systemName: "speaker.slash.fill") {
              setRumbleValues(left: 0, right: 0, lt: 0, rt: 0)
            }
          }
          HStack(spacing: 8) {
            if let rumbleResult {
              Text("Last rumble: \(rumbleResult)").font(.caption).foregroundColor(.secondary)
            } else {
              Text("Rumble changes only affect the physical controller.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func rumbleIconButton(
    _ title: String,
    systemName: String,
    action: @escaping () -> Void
  ) -> some View {
    SwiftUI.Button(action: action) {
      if #available(macOS 11.0, *) {
        VStack(spacing: 3) {
          Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
          Text(rumbleGlyphCaption(title))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
        }
        .frame(width: 44, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
      } else {
        Text(title)
          .font(.caption)
          .frame(width: 44, height: 36)
      }
    }
    .buttonStyle(.borderless)
  }

  private func rumbleGlyphCaption(_ title: String) -> String {
    switch title {
    case "Sending": return "..."
    case "Pulse": return "pulse"
    case "Hold": return "hold"
    case "Stop": return "stop"
    case "Left motor": return "L"
    case "Right motor": return "R"
    case "Low": return "low"
    case "Mid": return "mid"
    case "Max": return "max"
    case "Zero": return "zero"
    default: return title
    }
  }

  private func sendRumble(
    to device: DeviceViewModel,
    left: UInt8? = nil,
    right: UInt8? = nil,
    lt: UInt8? = nil,
    rt: UInt8? = nil,
    durationMs: Int? = nil
  ) {
    rumbleRunning = true
    rumbleResult = nil
    Task {
      let ok = await model.sendPhysicalRumble(
        vendorID: device.vendorID,
        productID: device.productID,
        left: left ?? UInt8(clamping: Int(rumbleLeft)),
        right: right ?? UInt8(clamping: Int(rumbleRight)),
        lt: lt ?? UInt8(clamping: Int(rumbleLT)),
        rt: rt ?? UInt8(clamping: Int(rumbleRT)),
        durationMs: durationMs ?? Int(rumbleDurationMs)
      )
      rumbleResult = ok ? "sent" : "not available"
      rumbleRunning = false
    }
  }

  private func setRumbleValues(left: Double, right: Double, lt: Double, rt: Double) {
    rumbleLeft = left
    rumbleRight = right
    rumbleLT = lt
    rumbleRT = rt
  }

  private var packetLogView: some View {
    OJDCard(title: "Recent packets") {
      VStack(alignment: .leading, spacing: 8) {
        if packetLog.isEmpty {
          Text("No packets captured yet.").font(.caption).foregroundColor(.secondary)
        } else {
          ForEach(Array(packetLog.suffix(8).enumerated()), id: \.offset) { _, entry in
            Text("\(entry.direction) \(entry.length)b \(entry.hex)")
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)
              .padding(.vertical, 1)
          }
        }
      }
    }
  }

  private var packetLogToggle: some View {
    SwiftUI.Button {
      showPackets.toggle()
    } label: {
      HStack {
        Text(showPackets ? "Hide packet log" : "Show packet log")
        Spacer()
        if #available(macOS 11.0, *) {
          Image(systemName: showPackets ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .semibold))
        } else {
          Text(showPackets ? "▴" : "▾")
        }
      }
      .font(.caption.weight(.semibold))
      .foregroundColor(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.secondary.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
  }

  private func startRefreshTasks() {
    if stateTask == nil {
      stateTask = Task {
        while !Task.isCancelled {
          await refreshState()
          try? await Task.sleep(nanoseconds: inputRefreshIntervalNanoseconds)
        }
      }
    }
    if packetLogTask == nil {
      packetLogTask = Task {
        await refreshPacketLog()
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: packetLogRefreshIntervalNanoseconds)
          await refreshPacketLog()
        }
      }
    }
  }

  private func refreshState() async {
    guard let device = selectedDevice else {
      state = nil
      return
    }
    let nextState = await sampler.deviceInputState(
      vendorID: device.vendorID,
      productID: device.productID
    )
    if state != nextState {
      state = nextState
    }
  }

  private func refreshPacketLog() async {
    guard let device = selectedDevice else {
      packetLog = []
      return
    }
    packetLog = await sampler.packetLog(vendorID: device.vendorID, productID: device.productID)
  }
}

private struct RumbleSlider: View {
  let label: String
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .frame(width: 34, alignment: .leading)
      Slider(value: $value, in: 0...255, step: 1)
        .frame(width: 116)
      Text("\(Int(value))")
        .font(.system(.caption, design: .monospaced))
        .frame(width: 30, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct AxisMeter: View {
  let label: String
  let value: Float
  let range: ClosedRange<Float>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.caption.weight(.semibold))
        Spacer()
        Text(String(format: "%.3f", value))
          .font(.system(.caption, design: .monospaced))
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.18))
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor)
            .frame(width: max(4, proxy.size.width * normalizedValue))
        }
      }
      .frame(width: 140, height: 7)
      .transaction { transaction in
        transaction.animation = nil
      }
    }
  }

  private var normalizedValue: CGFloat {
    let width = range.upperBound - range.lowerBound
    guard width > 0 else { return 0.0 }
    let normalized = (value - range.lowerBound) / width
    return CGFloat(max(0, min(1, normalized)))
  }
}
