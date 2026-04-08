import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State private var runningSelfTest = false
  @State private var showUninstallConfirm = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        headerRow
        Divider()
        daemonRow
        driverKitRow
        modeRow
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
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Driver").font(.subheadline)
        Spacer()
        Text(model.daemonConnected ? "running" : (model.daemonInstalled ? "installed" : "missing"))
          .font(.caption)
          .foregroundStyle(model.daemonConnected ? .green : .secondary)
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

          SwiftUI.Button("Uninstall", role: .destructive) { showUninstallConfirm = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        Text("Generic (HID GamePad)").tag(CompatibilityIdentity.generic.rawValue)
        Text("Xbox One (HID)").tag(CompatibilityIdentity.xboxOne.rawValue)
        Text("Xbox 360 (experimental)").tag(CompatibilityIdentity.xbox360.rawValue)
      }
      .pickerStyle(.menu)
      .disabled(!model.daemonConnected || !compatSelected)

      Text("Used only in Compatibility mode. If inputs stop working, set this back to Generic.")
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
