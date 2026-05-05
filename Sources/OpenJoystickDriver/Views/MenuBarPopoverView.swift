import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State private var runningSelfTest = false
  @State private var showUninstallConfirm = false
  @State private var inputTester = InputTestWindowController()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        headerRow
        Divider()
        daemonRow
        driverKitRow
        modeRow
        inputTestRow
        selfTestRow
        Divider()
        footerRow
      }
      .padding(12)
    }
    .frame(width: 420)
    .onAppear {
      Task {
        await model.syncFromDaemonNow()
        model.extensionManager.refreshInstallState()
      }
    }
    .confirmationDialog(
      "Uninstall LaunchAgent?",
      isPresented: $showUninstallConfirm,
      titleVisibility: .visible
    ) {
      SwiftUI.Button("Uninstall", role: .destructive) {
        Task {
          await model.uninstallDaemon()
          await model.syncFromDaemonNow()
        }
      }
      SwiftUI.Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the LaunchAgent plist. You can reinstall later.")
    }
  }

  private var headerRow: some View {
    HStack {
      Text("OpenJoystickDriver").font(.headline)
      Spacer()
      SwiftUI.Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
    }
  }

  private var daemonRow: some View {
    let daemonStatusLabel =
      model.daemonRestarting
      ? "restarting..."
      : (model.daemonConnected ? "running" : (model.daemonInstalled ? "installed" : "missing"))
    let daemonStatusColor: Color =
      model.daemonRestarting ? .orange : (model.daemonConnected ? .green : .secondary)

    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Driver").font(.subheadline)
        Spacer()
        Text(daemonStatusLabel)
          .font(.caption)
          .foregroundStyle(daemonStatusColor)
      }

      Text("Controllers: \(model.devices.count)").font(.caption2).foregroundStyle(.secondary)
      Text("Input Monitoring: \(model.inputMonitoring)").font(.caption2).foregroundStyle(.secondary)

      if let h = model.daemonHealth, h.installed {
        let state = h.state ?? "unknown"
        let pid = h.pid.map { "\($0)" } ?? "?"
        let active = h.activeCount.map { "\($0)" } ?? "?"
        let runs = h.runs.map { "\($0)" } ?? "?"
        let reason = h.isInefficientKillLoop ? (h.immediateReason ?? h.blame) : nil
        HStack(spacing: 8) {
          Text(
            "launchd: state=\(state), pid=\(pid), active=\(active), runs=\(runs)\(reason.map { ", \($0)" } ?? "")"
          )
            .font(.caption2)
            .foregroundStyle(h.isInefficientKillLoop ? .orange : .secondary)
            .lineLimit(2)
          Spacer()
          SwiftUI.Button("↻") {
            Task { await model.refreshDaemonHealth() }
          }
          .buttonStyle(.borderless)
          .help("Refresh launchd status")
        }
      }

      HStack(spacing: 8) {
        if !model.daemonInstalled {
          SwiftUI.Button("Install") {
            Task {
              await model.installDaemon()
              await model.syncFromDaemonNow()
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        } else {
          SwiftUI.Button("Start") {
            Task {
              await model.startDaemon()
              await model.syncFromDaemonNow()
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(model.daemonConnected)
          SwiftUI.Button("Restart") {
            Task {
              await model.restartDaemon()
              await model.syncFromDaemonNow()
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.daemonRestarting)

          SwiftUI.Button("Uninstall", role: .destructive) { showUninstallConfirm = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.daemonRestarting)
        }
        Spacer()
      }

      if let err = model.daemonError {
        Text(err).font(.caption2).foregroundStyle(.red)
      }
    }
  }

  private var driverKitRow: some View {
    let state = model.extensionManager.installState
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("DriverKit").font(.subheadline)
        Spacer()
        Text(state.label).font(.caption).foregroundStyle(state.isInstalled ? .green : .secondary)
        SwiftUI.Button("Install") { model.extensionManager.installExtension() }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(state.isInstalled || state.isPending)
      }
      if case .failed(let msg) = state {
        Text(msg)
          .font(.caption2)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)

        if !model.extensionManager.lastInstallDetails.isEmpty {
          DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(model.extensionManager.lastInstallDetails, id: \.self) { line in
                Text(line).font(.caption2).foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
            }
            .padding(.top, 4)
          }
          .font(.caption2)
        }
      }
      if let w = model.extensionManager.installWarning, state.isInstalled {
        Text(w)
          .font(.caption2)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
        let last = s.lastErrorHex ?? "none"
        Text("setReport: ok \(s.successes) / fail \(s.failures) (last \(last))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var modeRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Mode").font(.caption).foregroundStyle(.secondary)
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

      let requestedLabel: String = {
        switch model.virtualDeviceMode {
        case VirtualDeviceMode.auto.rawValue: return "Auto"
        case VirtualDeviceMode.driverKit.rawValue: return "DriverKit"
        case VirtualDeviceMode.compatUserSpace.rawValue: return "Compatibility"
        case VirtualDeviceMode.both.rawValue: return "Both"
        default: return model.virtualDeviceMode
        }
      }()
      Text("Requested mode: \(requestedLabel)")
        .font(.caption2)
        .foregroundStyle(.secondary)

      let activeLabel: String = {
        switch model.outputMode {
        case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return "DriverKit"
        case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue: return "Compatibility (user-space)"
        case CompositeOutputDispatcher.Mode.both.rawValue: return "Both"
        default: return "unknown"
        }
      }()
      Text("Active output: \(activeLabel)").font(.caption2).foregroundStyle(.secondary)

      let compatSelected = model.virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
      Picker(
        "Compatibility identity",
        selection: Binding(
          get: { model.compatibilityIdentity },
          set: { v in Task { await model.setCompatibilityIdentity(v) } }
        )
      ) {
        Text("SDL macOS").tag(CompatibilityIdentity.sdlMacOS.rawValue)
        Text("Generic HID").tag(CompatibilityIdentity.genericHID.rawValue)
        Text("Xbox 360 HID").tag(CompatibilityIdentity.x360HID.rawValue)
        Text("Xbox One HID").tag(CompatibilityIdentity.xoneHID.rawValue)
      }
      .pickerStyle(.menu)
      .disabled(!model.daemonConnected || !compatSelected)

      Text("Used only in Compatibility mode. SDL macOS is the default for Steam, PCSX2, and SDL apps.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      Text("Compatibility backend: \(model.userSpaceVirtualDeviceStatus)")
        .font(.caption2)
        .foregroundStyle(
          model.userSpaceVirtualDeviceStatus.hasPrefix("error:") ? .orange : .secondary
        )
    }
  }

  private var selfTestRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Self-test").font(.subheadline)
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
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!model.daemonConnected || runningSelfTest)
      }
      if let t = model.virtualDeviceSelfTest {
        Text("DriverKit: value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)")
          .font(.caption2)
          .foregroundStyle(.secondary)
        if let delta = t.driverKitInputReportDelta {
          Text("DriverKit (ioreg): input report Δ \(delta)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        if let delta = t.driverKitSetReportSuccessDelta {
          Text("DriverKit (daemon): setReport ok Δ \(delta)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text("User-space: value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      } else {
        Text("Press buttons while it runs.").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private var inputTestRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Input test").font(.subheadline)
        Spacer()
        SwiftUI.Button("Open") {
          inputTester.show(model: model)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!model.daemonConnected)
        .accessibilityLabel("Open input test window")
      }
      Text("Live physical input, packet log, and physical rumble test.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
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

      Spacer()
    }
    .font(.caption)
  }
}

@MainActor private final class InputTestWindowController {
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
    newWindow.setContentSize(NSSize(width: 760, height: 620))
    newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    newWindow.isReleasedWhenClosed = false
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = newWindow
  }
}

private struct InputTestWindowView: View {
  @EnvironmentObject var model: AppModel
  @State private var selectedDeviceID: String?
  @State private var state: DeviceInputState?
  @State private var packetLog: [PacketLogEntry] = []
  @State private var rumbleRunning = false
  @State private var rumbleResult: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      if let device = selectedDevice {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            deviceSummary(device)
            axesGrid
            buttonGrid
            outputTestRow(device)
            packetLogView
          }
          .padding(.trailing, 8)
        }
      } else {
        VStack(spacing: 10) {
          Image(systemName: "gamecontroller")
            .font(.system(size: 42))
            .foregroundStyle(.secondary)
          Text("No controller selected").font(.headline)
          Text("Connect a controller or restart the daemon, then refresh.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(14)
    .frame(minWidth: 700, minHeight: 560)
    .onAppear {
      selectedDeviceID = selectedDeviceID ?? model.devices.first?.id
    }
    .task(id: selectedDevice?.id ?? "") {
      while !Task.isCancelled {
        await refreshState()
        try? await Task.sleep(for: .milliseconds(33))
      }
    }
    .task(id: selectedDevice?.id ?? "") {
      await refreshPacketLog()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        await refreshPacketLog()
      }
    }
  }

  private var selectedDevice: DeviceViewModel? {
    if let selectedDeviceID, let selected = model.devices.first(where: { $0.id == selectedDeviceID }) {
      return selected
    }
    return model.devices.first
  }

  private var header: some View {
    HStack(spacing: 10) {
      Text("Input Test").font(.title2.weight(.semibold))
      Spacer()
      Picker("Controller", selection: Binding(get: {
        selectedDevice?.id ?? ""
      }, set: { value in
        selectedDeviceID = value
      })) {
        ForEach(model.devices) { device in
          Text(device.name).tag(device.id)
        }
      }
      .frame(width: 260)
      .disabled(model.devices.isEmpty)
      SwiftUI.Button("Refresh") {
        Task {
          await model.syncFromDaemonNow()
          await refreshState()
          await refreshPacketLog()
        }
      }
    }
  }

  private func deviceSummary(_ device: DeviceViewModel) -> some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
      GridRow {
        Text("Device").foregroundStyle(.secondary)
        Text(device.name)
      }
      GridRow {
        Text("VID:PID").foregroundStyle(.secondary)
        Text(String(format: "%04X:%04X", device.vendorID, device.productID))
      }
      GridRow {
        Text("Parser").foregroundStyle(.secondary)
        Text(device.parser)
      }
      GridRow {
        Text("Connection").foregroundStyle(.secondary)
        Text(device.connection)
      }
    }
    .font(.caption)
  }

  private var axesGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
      GridRow {
        AxisMeter(label: "LX", value: state?.leftStickX ?? 0, range: -1...1)
        AxisMeter(label: "LY", value: state?.leftStickY ?? 0, range: -1...1)
      }
      GridRow {
        AxisMeter(label: "RX", value: state?.rightStickX ?? 0, range: -1...1)
        AxisMeter(label: "RY", value: state?.rightStickY ?? 0, range: -1...1)
      }
      GridRow {
        AxisMeter(label: "LT", value: state?.leftTrigger ?? 0, range: 0...1)
        AxisMeter(label: "RT", value: state?.rightTrigger ?? 0, range: 0...1)
      }
    }
  }

  private var buttonGrid: some View {
    let pressed = Set(state?.pressedButtons ?? [])
    return VStack(alignment: .leading, spacing: 8) {
      Text("Buttons").font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
        ForEach(Button.allCases, id: \.rawValue) { button in
          let isDown = pressed.contains(button.rawValue)
          Text(button.displayName)
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(isDown ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.14))
            .foregroundStyle(isDown ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(button.displayName)
            .accessibilityValue(isDown ? "pressed" : "released")
        }
      }
    }
  }

  private func outputTestRow(_ device: DeviceViewModel) -> some View {
    let canRumble = device.supportsPhysicalRumble
    return VStack(alignment: .leading, spacing: 8) {
      Text("Physical output").font(.headline)
      HStack {
        SwiftUI.Button(rumbleRunning ? "Rumbling..." : "Rumble pulse") {
          rumbleRunning = true
          rumbleResult = nil
          Task {
            let ok = await model.sendPhysicalRumble(
              vendorID: device.vendorID,
              productID: device.productID,
              left: 180,
              right: 180,
              lt: 120,
              rt: 120,
              durationMs: 450
            )
            rumbleResult = ok ? "sent" : "not available"
            rumbleRunning = false
          }
        }
        .disabled(rumbleRunning || !canRumble)
        .accessibilityLabel("Send physical rumble pulse")
        Text("Rumble: \(canRumble ? "supported" : "not supported")")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("LED: not exposed")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let rumbleResult {
          Text("Rumble: \(rumbleResult)").font(.caption).foregroundStyle(.secondary)
        }
      }
      Text("LED needs a verified per-protocol command surface before it becomes a live control.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var packetLogView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent packets").font(.headline)
      if packetLog.isEmpty {
        Text("No packets captured yet.").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(Array(packetLog.suffix(12).enumerated()), id: \.offset) { _, entry in
          Text("\(entry.direction) \(entry.length)b \(entry.hex)")
            .font(.system(.caption2, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(2)
        }
      }
    }
  }

  private func refreshState() async {
    guard let device = selectedDevice else {
      state = nil
      return
    }
    state = await model.deviceInputState(vendorID: device.vendorID, productID: device.productID)
  }

  private func refreshPacketLog() async {
    guard let device = selectedDevice else {
      packetLog = []
      return
    }
    packetLog = await model.packetLog(vendorID: device.vendorID, productID: device.productID)
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
      .frame(width: 300, height: 8)
      .transaction { transaction in
        transaction.animation = nil
      }
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.3f", value))
    }
  }

  private var normalizedValue: CGFloat {
    let width = range.upperBound - range.lowerBound
    guard width > 0 else { return 0.0 }
    let normalized = (value - range.lowerBound) / width
    return CGFloat(max(0, min(1, normalized)))
  }
}
