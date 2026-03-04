import AppKit
import SwiftUI

struct DiagnosticsView: View {
  @EnvironmentObject var model: AppModel
  @State private var showTips = false
  @State private var daemonAction: String?
  @State private var showUninstallConfirm = false

  private let daemonLogPath = "/tmp/com.openjoystickdriver.daemon.out"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        statusCard
        controllersCard
        daemonLifecycleCard
        logCard
      }.padding()
    }.navigationTitle("Diagnostics").toolbar {
      ToolbarItem {
        SwiftUI.Button {
          showTips.toggle()
        } label: {
          Label("Troubleshooting Tips", systemImage: "lightbulb")
        }.help("Show troubleshooting tips").popover(isPresented: $showTips, arrowEdge: .bottom) {
          tipsPopover
        }
      }
      ToolbarItem {
        SwiftUI.Button {
          copyDiagnostics()
        } label: {
          Label("Copy Diagnostics", systemImage: "doc.on.doc")
        }.help("Copy diagnostics to clipboard")
      }
    }
  }

  // MARK: - Status Helpers

  private var daemonStatusText: String {
    if model.daemonRestarting { return "Restarting..." }
    if let action = daemonAction { return action }
    if model.daemonConnected { return "Running" }
    if model.daemonInstalled { return "Installed (not running)" }
    return "Not installed"
  }

  private var daemonStatusColor: Color {
    if model.daemonRestarting { return .orange }
    if daemonAction != nil { return .orange }
    if model.daemonConnected { return .green }
    if model.daemonInstalled { return .orange }
    return .secondary
  }

  // MARK: - Cards

  /// Merged system + permissions overview card.
  private var statusCard: some View {
    GroupBox {
      VStack(spacing: 8) {
        labeledRow("macOS") {
          Text(ProcessInfo.processInfo.operatingSystemVersionString).foregroundStyle(.secondary)
        }
        Divider()
        labeledRow("Daemon") {
          HStack(spacing: 4) {
            Circle().fill(daemonStatusColor).frame(width: 7, height: 7)
            Text(daemonStatusText).foregroundStyle(daemonStatusColor)
          }
        }
        Divider()
        labeledRow("Input Monitoring") {
          PermissionStatusIcon(isGranted: model.inputMonitoring.lowercased() == "granted")
        }
        Divider()
        labeledRow("Accessibility") {
          PermissionStatusIcon(isGranted: model.accessibility.lowercased() == "granted")
        }
      }
    } label: {
      Label("Status", systemImage: "checkmark.shield").fontWeight(.semibold)
    }
  }

  private var daemonLifecycleCard: some View {
    GroupBox {
      VStack(spacing: 10) {
        if !model.daemonInstalled {
          installButton
        } else {
          if !model.daemonConnected { startButton }
          if model.daemonInstalled { restartButton }
          uninstallButton
        }
        if let err = model.daemonError { Text(err).font(.caption).foregroundStyle(.red) }
      }
    } label: {
      Label("Daemon Lifecycle", systemImage: "arrow.triangle.2.circlepath").fontWeight(.semibold)
    }.confirmationDialog(
      "Uninstall Daemon?",
      isPresented: $showUninstallConfirm,
      titleVisibility: .visible
    ) {
      SwiftUI.Button("Uninstall", role: .destructive) {
        daemonAction = "Uninstalling..."
        Task {
          await model.uninstallDaemon()
          daemonAction = nil
        }
      }
      SwiftUI.Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the LaunchAgent plist. You can reinstall later.")
    }
  }

  private var installButton: some View {
    SwiftUI.Button {
      daemonAction = "Installing..."
      Task {
        await model.installDaemon()
        daemonAction = nil
      }
    } label: {
      Text("Install LaunchAgent").frame(maxWidth: .infinity)
    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(daemonAction != nil)
  }

  private var startButton: some View {
    SwiftUI.Button {
      daemonAction = "Starting..."
      Task {
        await model.startDaemon()
        daemonAction = nil
      }
    } label: {
      Text("Start Daemon").frame(maxWidth: .infinity)
    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(daemonAction != nil)
  }

  private var restartButton: some View {
    SwiftUI.Button {
      daemonAction = "Restarting..."
      Task {
        await model.restartDaemon()
        daemonAction = nil
      }
    } label: {
      Text("Restart Daemon").frame(maxWidth: .infinity)
    }.buttonStyle(.bordered).controlSize(.large).disabled(daemonAction != nil)
  }

  private var uninstallButton: some View {
    SwiftUI.Button(role: .destructive) {
      showUninstallConfirm = true
    } label: {
      Text("Uninstall LaunchAgent").frame(maxWidth: .infinity)
    }.buttonStyle(.bordered).controlSize(.large).disabled(daemonAction != nil)
  }

  private var controllersCard: some View {
    GroupBox {
      if model.devices.isEmpty {
        HStack {
          Image(systemName: "gamecontroller").foregroundStyle(.tertiary)
          Text("No controllers connected").foregroundStyle(.secondary).font(.callout)
        }
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
            if index > 0 { Divider() }
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(device.name).fontWeight(.medium)
                Spacer()
                protocolBadge(device.parser)
              }
              HStack(spacing: 12) {
                Text(String(format: "VID 0x%04X  PID 0x%04X", device.vendorID, device.productID))
                  .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Text(device.connection).font(.caption).foregroundStyle(.tertiary)
                if let sn = device.serialNumber {
                  Text("SN: \(sn)").font(.caption).foregroundStyle(.tertiary).textSelection(
                    .enabled
                  )
                }
              }
            }.padding(.vertical, 6)
          }
        }
      }
    } label: {
      Label("Controllers", systemImage: "gamecontroller").fontWeight(.semibold)
    }
  }

  private func protocolBadge(_ parser: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: protocolIcon(for: parser)).imageScale(.small)
      Text(parser)
    }.font(.caption).fontWeight(.medium).padding(.horizontal, 8).padding(.vertical, 3).background(
      protocolColor(for: parser).opacity(0.15)
    ).foregroundStyle(protocolColor(for: parser)).clipShape(Capsule())
  }

  private var logCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Text(daemonLogPath).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
          .textSelection(.enabled)
        SwiftUI.Button("Show in Finder") {
          NSWorkspace.shared.selectFile(daemonLogPath, inFileViewerRootedAtPath: "")
        }.font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
      }
    } label: {
      Label("Daemon Log", systemImage: "doc.text").fontWeight(.semibold)
    }
  }

  // MARK: - Troubleshooting

  private var tipsPopover: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Troubleshooting Tips").font(.headline)
      Divider()
      tipRow(
        "USB access denied",
        detail: "Run daemon with sudo, or sign with the USB Device"
          + " entitlement (scripts/build-release.sh)."
      )
      tipRow(
        "Accessibility not granted",
        detail: "System Settings › Privacy › Accessibility - add the daemon binary."
      )
      tipRow(
        "Daemon not running",
        detail: "Use Start Daemon in the Daemon Lifecycle card."
          + " Running with sudo puts the daemon in root's bootstrap namespace,"
          + " which breaks XPC communication."
      )
      tipRow(
        "No events in games",
        detail: "The target app must be focused."
          + " CGEvents only dispatch to the active application."
      )
    }.padding().frame(width: 320)
  }

  // MARK: - Helpers

  private func labeledRow<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
    HStack {
      Text(title).foregroundStyle(.primary)
      Spacer()
      value()
    }
  }

  private func tipRow(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\u{2022} \(title)").fontWeight(.medium)
      Text(detail).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func copyDiagnostics() {
    let version = ProcessInfo.processInfo.operatingSystemVersionString
    var lines: [String] = [
      "OpenJoystickDriver Diagnostics", "==============================", "macOS: \(version)",
      "Daemon: \(daemonStatusText)", "Input Monitoring: \(model.inputMonitoring)",
      "Accessibility: \(model.accessibility)", "", "Controllers:",
    ]
    if model.devices.isEmpty {
      lines.append("  (none)")
    } else {
      for device in model.devices {
        lines.append(
          "  \(device.name)" + " \u{2014} VID: \(device.vendorID)," + " PID: \(device.productID),"
            + " Parser: \(device.parser)"
        )
      }
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
  }
}
