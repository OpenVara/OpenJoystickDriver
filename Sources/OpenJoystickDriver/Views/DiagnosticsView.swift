import AppKit
import SwiftUI

struct DiagnosticsView: View {
  @EnvironmentObject var model: AppModel
  @State private var showTips = false
  @State private var managingDaemon = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        diagnosticsForm
        troubleshootingSection
        copyButton
      }
    }.navigationTitle("Diagnostics")
  }

  private var daemonStatusText: String {
    model.daemonConnected
      ? "Running" : model.daemonInstalled ? "Installed (not running)" : "Not installed"
  }

  private var daemonStatusColor: Color {
    model.daemonConnected ? .green : model.daemonInstalled ? .orange : .secondary
  }

  private var diagnosticsForm: some View {
    Form {
      Section("System") {
        LabeledContent("macOS Version") {
          Text(ProcessInfo.processInfo.operatingSystemVersionString)
        }
        LabeledContent("Daemon") { Text(model.daemonConnected ? "Connected" : "Not running") }
      }
      Section("Daemon Lifecycle") {
        LabeledContent("Status") { Text(daemonStatusText).foregroundStyle(daemonStatusColor) }
        if !model.daemonInstalled {
          SwiftUI.Button("Install LaunchAgent") {
            managingDaemon = true
            Task {
              await model.installDaemon()
              managingDaemon = false
            }
          }.disabled(managingDaemon)
        } else {
          SwiftUI.Button("Uninstall LaunchAgent", role: .destructive) {
            managingDaemon = true
            Task {
              await model.uninstallDaemon()
              managingDaemon = false
            }
          }.disabled(managingDaemon)
        }
        if let err = model.daemonError { Text(err).font(.caption).foregroundStyle(.red) }
      }
      Section("Permissions") {
        LabeledContent("Input Monitoring", value: model.inputMonitoring)
        LabeledContent("Accessibility", value: model.accessibility)
      }
      Section("Controllers") {
        if model.devices.isEmpty {
          Text("No devices connected").foregroundStyle(.secondary)
        } else {
          ForEach(model.devices) { device in LabeledContent(device.name, value: device.parser) }
        }
      }
    }.formStyle(.grouped)
  }

  private var troubleshootingSection: some View {
    DisclosureGroup("Troubleshooting Tips", isExpanded: $showTips) {
      VStack(alignment: .leading, spacing: 8) {
        tipRow(
          "USB access denied",
          detail: "Run daemon with sudo, or sign" + " with USB Device entitlement"
            + " (scripts/build-release.sh)."
        )
        tipRow(
          "Accessibility not granted",
          detail: "Go to System Settings >" + " Privacy > Accessibility" + " and add daemon."
        )
        tipRow(
          "Daemon not running",
          detail: "Use 'Install LaunchAgent' above" + " to auto-start on login, or run:"
            + " sudo OpenJoystickDriverDaemon"
        )
        tipRow(
          "No events in games",
          detail: "Game may need to be focused." + " CGEvents only work when"
            + " target app is active."
        )
      }.padding(.top, 4)
    }.padding(.horizontal)
  }

  private var copyButton: some View {
    HStack {
      Spacer()
      SwiftUI.Button("Copy Diagnostics to Clipboard") { copyDiagnostics() }.buttonStyle(.bordered)
      Spacer()
    }.padding()
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
