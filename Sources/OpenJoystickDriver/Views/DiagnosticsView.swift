import AppKit
import SwiftUI

struct DiagnosticsView: View {
  @EnvironmentObject var model: AppModel
  @State private var showTips = false
  @State private var managingDaemon = false

  private let daemonLogPath = "/tmp/com.openjoystickdriver.daemon.out"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        systemCard
        daemonLifecycleCard
        permissionsCard
        controllersCard
        logPathCard
        troubleshootingSection
      }
      .padding()
    }
    .navigationTitle("Diagnostics")
    .toolbar {
      ToolbarItem {
        SwiftUI.Button {
          copyDiagnostics()
        } label: {
          Label(
            "Copy Diagnostics",
            systemImage: "doc.on.doc"
          )
        }
        .help("Copy diagnostics to clipboard")
      }
    }
  }

  // MARK: - Status Helpers

  private var daemonStatusText: String {
    if model.daemonConnected { return "Running" }
    if model.daemonInstalled {
      return "Installed (not running)"
    }
    return "Not installed"
  }

  private var daemonStatusColor: Color {
    if model.daemonConnected { return .green }
    if model.daemonInstalled { return .orange }
    return .secondary
  }

  // MARK: - Cards

  private var systemCard: some View {
    GroupBox {
      VStack(spacing: 8) {
        labeledRow("macOS Version") {
          Text(
            ProcessInfo.processInfo
              .operatingSystemVersionString
          )
        }
        Divider()
        labeledRow("Daemon") {
          HStack(spacing: 4) {
            Circle()
              .fill(daemonStatusColor)
              .frame(width: 7, height: 7)
            Text(daemonStatusText)
              .foregroundStyle(daemonStatusColor)
          }
        }
      }
    } label: {
      Label("System", systemImage: "desktopcomputer")
        .fontWeight(.semibold)
    }
  }

  private var daemonLifecycleCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        if !model.daemonInstalled {
          SwiftUI.Button("Install LaunchAgent") {
            managingDaemon = true
            Task {
              await model.installDaemon()
              managingDaemon = false
            }
          }
          .disabled(managingDaemon)
        } else {
          if !model.daemonConnected {
            SwiftUI.Button("Start Daemon") {
              managingDaemon = true
              Task {
                await model.startDaemon()
                managingDaemon = false
              }
            }
            .disabled(managingDaemon)
          }
          if model.daemonInstalled {
            SwiftUI.Button("Restart Daemon") {
              managingDaemon = true
              Task {
                await model.restartDaemon()
                managingDaemon = false
              }
            }
            .disabled(managingDaemon)
          }
          SwiftUI.Button(
            "Uninstall LaunchAgent",
            role: .destructive
          ) {
            managingDaemon = true
            Task {
              await model.uninstallDaemon()
              managingDaemon = false
            }
          }
          .disabled(managingDaemon)
        }
        if let err = model.daemonError {
          Text(err)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    } label: {
      Label("Daemon Lifecycle", systemImage: "arrow.triangle.2.circlepath")
        .fontWeight(.semibold)
    }
  }

  private var permissionsCard: some View {
    GroupBox {
      VStack(spacing: 8) {
        labeledRow("Input Monitoring") {
          permissionPill(model.inputMonitoring)
        }
        Divider()
        labeledRow("Accessibility") {
          permissionPill(model.accessibility)
        }
      }
    } label: {
      Label("Permissions", systemImage: "lock.shield")
        .fontWeight(.semibold)
    }
  }

  private var controllersCard: some View {
    GroupBox {
      if model.devices.isEmpty {
        Text("No devices connected")
          .foregroundStyle(.secondary)
          .font(.callout)
      } else {
        VStack(spacing: 8) {
          ForEach(
            Array(model.devices.enumerated()),
            id: \.element.id
          ) { index, device in
            if index > 0 { Divider() }
            labeledRow(device.name) {
              Text(device.parser)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
          }
        }
      }
    } label: {
      Label("Controllers", systemImage: "gamecontroller")
        .fontWeight(.semibold)
    }
  }

  private var logPathCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 4) {
        Text("Daemon stdout/stderr log:")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(daemonLogPath)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    } label: {
      Label("Log Path", systemImage: "doc.text")
        .fontWeight(.semibold)
    }
  }

  // MARK: - Troubleshooting

  private var troubleshootingSection: some View {
    DisclosureGroup(
      "Troubleshooting Tips",
      isExpanded: $showTips
    ) {
      VStack(alignment: .leading, spacing: 8) {
        tipRow(
          "USB access denied",
          detail: "Run daemon with sudo, or sign"
            + " with USB Device entitlement"
            + " (scripts/build-release.sh)."
        )
        tipRow(
          "Accessibility not granted",
          detail: "Go to System Settings >"
            + " Privacy > Accessibility"
            + " and add daemon."
        )
        tipRow(
          "Daemon not running",
          detail: "Use 'Start Daemon' above."
            + " Running with sudo puts daemon"
            + " in root's bootstrap namespace,"
            + " preventing XPC communication."
        )
        tipRow(
          "No events in games",
          detail: "Game may need to be focused."
            + " CGEvents only work when"
            + " target app is active."
        )
      }
      .padding(.top, 4)
    }
  }

  // MARK: - Helpers

  private func labeledRow<V: View>(
    _ title: String,
    @ViewBuilder value: () -> V
  ) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      value()
    }
  }

  private func permissionPill(_ status: String) -> some View {
    let granted = status.lowercased() == "granted"
    let label: String
    switch status.lowercased() {
    case "granted": label = "Granted"
    case "denied": label = "Denied"
    case "notdetermined": label = "Not Determined"
    default: label = status
    }
    return Text(label)
      .font(.caption)
      .fontWeight(.medium)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        granted
          ? Color.green.opacity(0.15)
          : Color.red.opacity(0.15)
      )
      .foregroundStyle(granted ? .green : .red)
      .clipShape(Capsule())
  }

  private func tipRow(
    _ title: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\u{2022} \(title)").fontWeight(.medium)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func copyDiagnostics() {
    let version = ProcessInfo.processInfo
      .operatingSystemVersionString
    var lines: [String] = [
      "OpenJoystickDriver Diagnostics",
      "==============================",
      "macOS: \(version)",
      "Daemon: \(daemonStatusText)",
      "Input Monitoring: \(model.inputMonitoring)",
      "Accessibility: \(model.accessibility)",
      "",
      "Controllers:",
    ]
    if model.devices.isEmpty {
      lines.append("  (none)")
    } else {
      for device in model.devices {
        lines.append(
          "  \(device.name)"
            + " \u{2014} VID: \(device.vendorID),"
            + " PID: \(device.productID),"
            + " Parser: \(device.parser)"
        )
      }
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      lines.joined(separator: "\n"),
      forType: .string
    )
  }
}
