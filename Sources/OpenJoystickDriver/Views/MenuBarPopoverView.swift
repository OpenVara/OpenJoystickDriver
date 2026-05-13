import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State private var runningSelfTest = false
  @State private var showUninstallConfirm = false
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
          .foregroundColor(daemonStatusColor)
      }

      Text("Controllers: \(model.devices.count)").font(.caption).foregroundColor(.secondary)
      Text("Input Monitoring: \(model.inputMonitoring)").font(.caption).foregroundColor(.secondary)

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
            .font(.caption)
            .foregroundColor(h.isInefficientKillLoop ? .orange : .secondary)
            .lineLimit(2)
          Spacer()
          SwiftUI.Button("↻") {
            Task { await model.refreshDaemonHealth() }
          }
          .buttonStyle(.borderless)
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
          .buttonStyle(.borderless)
          .controlSize(.small)
        } else {
          SwiftUI.Button("Start") {
            Task {
              await model.startDaemon()
              await model.syncFromDaemonNow()
            }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(model.daemonConnected)
          SwiftUI.Button("Restart") {
            Task {
              await model.restartDaemon()
              await model.syncFromDaemonNow()
            }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(model.daemonRestarting)

          SwiftUI.Button("Uninstall") { showUninstallConfirm = true }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(model.daemonRestarting)
        }
        Spacer()
      }

      if let err = model.daemonError {
        Text(err).font(.caption).foregroundColor(.red)
      }
    }
  }

  private var driverKitRow: some View {
    let state = model.extensionManager.installState
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("DriverKit").font(.subheadline)
        Spacer()
        Text(state.label).font(.caption).foregroundColor(state.isInstalled ? .green : .secondary)
        SwiftUI.Button("Install") { model.extensionManager.installExtension() }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(state.isInstalled || state.isPending)
      }
      if case .failed(let msg) = state {
        Text(msg)
          .font(.caption)
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)

        if !model.extensionManager.lastInstallDetails.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            Text("Details").font(.caption)
            ForEach(model.extensionManager.lastInstallDetails, id: \.self) { line in
              Text(line).font(.caption).foregroundColor(.secondary)
            }
          }
          .padding(.top, 4)
        }
      }
      if let w = model.extensionManager.installWarning, state.isInstalled {
        Text(w)
          .font(.caption)
          .foregroundColor(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
        let last = s.lastErrorHex ?? "none"
        Text("setReport: ok \(s.successes) / fail \(s.failures) (last \(last))")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private var modeRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Mode").font(.caption).foregroundColor(.secondary)
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
        .font(.caption)
        .foregroundColor(.secondary)

      Text(
        "ⓘ Compatibility is the normal app/game mode. " +
          "DriverKit is for the system extension path; " +
          "Both is only for debugging duplicate-output issues."
      )
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      let activeLabel: String = {
        switch model.outputMode {
        case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return "DriverKit"
        case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue: return "Compatibility (user-space)"
        case CompositeOutputDispatcher.Mode.both.rawValue: return "Both"
        default: return "unknown"
        }
      }()
      Text("Active output: \(activeLabel)").font(.caption).foregroundColor(.secondary)

      let compatSelected = model.virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
      Picker(
        "Compatibility identity",
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
      .disabled(!model.daemonConnected || !compatSelected)

      Text(
        "ⓘ Pick SDL 2/3 for Steam, PCSX2, DuckStation, or Moonlight/SDL. " +
          "Pick Apple GameController for native macOS GCController apps. " +
          "Pick Generic HID for descriptor-driven apps."
      )
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Text("Compatibility backend: \(model.userSpaceVirtualDeviceStatus)")
        .font(.caption)
        .foregroundColor(
          model.userSpaceVirtualDeviceStatus.hasPrefix("error:") ? .orange : .secondary
        )

      Text("Apple GameController.framework support: \(gameControllerSupportLabel)")
        .font(.caption)
        .foregroundColor(gameControllerSupportLabel == "yes" ? .green : .secondary)
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
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!model.daemonConnected || runningSelfTest)
      }
      if let t = model.virtualDeviceSelfTest {
        Text("DriverKit: value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)")
          .font(.caption)
          .foregroundColor(.secondary)
        if let delta = t.driverKitInputReportDelta {
          Text("DriverKit (ioreg): input report Δ \(delta)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        if let delta = t.driverKitSetReportSuccessDelta {
          Text("DriverKit (daemon): setReport ok Δ \(delta)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        Text("User-space: value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        Text("Press buttons while it runs.").font(.caption).foregroundColor(.secondary)
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
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!model.daemonConnected)
      }
      Text("Live physical input, packet log, and physical rumble test.")
        .font(.caption)
        .foregroundColor(.secondary)
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
  private let compactSize = NSSize(width: 720, height: 500)
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

private struct InputTestWindowView: View {
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
  @State private var stateTask: Task<Void, Never>?
  @State private var packetLogTask: Task<Void, Never>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        header
        Divider()
        if let device = selectedDevice {
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
              compactDeviceSummary(device)
              axesGrid
              buttonGrid
            }
            .frame(width: 300, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
              outputTestRow(device)
              packetLogView
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
        } else {
          VStack(spacing: 10) {
            Text("No controller selected").font(.headline)
            Text("Connect a controller or restart the daemon, then refresh.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 420)
        }
      }
      .padding(16)
    }
    .frame(minWidth: 720, minHeight: 500)
    .onAppear {
      selectedDeviceID = selectedDeviceID ?? model.devices.first?.id
      startRefreshTasks()
    }
    .onDisappear {
      stateTask?.cancel()
      packetLogTask?.cancel()
      stateTask = nil
      packetLogTask = nil
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
      Text("Input Test")
        .font(.headline)
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

  private func compactDeviceSummary(_ device: DeviceViewModel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(device.name)
        .font(.headline)
        .lineLimit(1)
      HStack(spacing: 8) {
        Text(device.parser)
        Text(device.connection)
        Text(String(format: "%04X:%04X", device.vendorID, device.productID))
      }
      .font(.caption)
      .foregroundColor(.secondary)
    }
  }

  private var axesGrid: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Axes").font(.headline)
      HStack(spacing: 10) {
        AxisMeter(label: "LX", value: state?.leftStickX ?? 0, range: -1...1)
        AxisMeter(label: "LY", value: state?.leftStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 10) {
        AxisMeter(label: "RX", value: state?.rightStickX ?? 0, range: -1...1)
        AxisMeter(label: "RY", value: state?.rightStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 10) {
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
      Text("Buttons").font(.headline)
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
    return VStack(alignment: .leading, spacing: 6) {
      Text("Physical output").font(.headline)
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          RumbleSlider(label: "L", value: $rumbleLeft)
          RumbleSlider(label: "R", value: $rumbleRight)
        }
        VStack(alignment: .leading, spacing: 4) {
          RumbleSlider(label: "LT", value: $rumbleLT)
          RumbleSlider(label: "RT", value: $rumbleRT)
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
          Text("Rumble: \(canRumble ? "supported" : "not supported")")
            .font(.caption)
            .foregroundColor(.secondary)
          Text("LED: not exposed")
            .font(.caption)
            .foregroundColor(.secondary)
          if let rumbleResult {
            Text("Rumble: \(rumbleResult)").font(.caption).foregroundColor(.secondary)
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
    VStack(alignment: .leading, spacing: 6) {
      Text("Recent packets").font(.headline)
      if packetLog.isEmpty {
        Text("No packets captured yet.").font(.caption).foregroundColor(.secondary)
      } else {
        ForEach(Array(packetLog.suffix(8).enumerated()), id: \.offset) { _, entry in
          Text("\(entry.direction) \(entry.length)b \(entry.hex)")
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
        }
      }
    }
  }

  private func startRefreshTasks() {
    if stateTask == nil {
      stateTask = Task {
        while !Task.isCancelled {
          await refreshState()
          try? await Task.sleep(nanoseconds: 33_000_000)
        }
      }
    }
    if packetLogTask == nil {
      packetLogTask = Task {
        await refreshPacketLog()
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 1_000_000_000)
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

private struct RumbleSlider: View {
  let label: String
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .frame(width: 24, alignment: .leading)
      Slider(value: $value, in: 0...255, step: 1)
        .frame(width: 110)
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
