import AppKit
import SwiftUI
import OpenJoystickDriverKit

struct DiagnosticsView: View {
  @EnvironmentObject var model: AppModel
  @State private var showTips = false
  @State private var daemonAction: String?
  @State private var showUninstallConfirm = false
  @State private var refreshingVirtualDevices = false

  private let daemonLogPath = "/tmp/com.openjoystickdriver.daemon.out"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        statusCard
        controllersCard
        virtualDevicesCard
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
                ProtocolBadge(parser: device.parser)
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

  private var virtualDevicesCard: some View {
    let diag = model.virtualDeviceDiagnostics
    return GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        if let diag {
          let modeLabel: String =
            diag.outputMode == "secondaryOnly" ? "User-space only"
            : (diag.outputMode == "both" ? "DriverKit + User-space" : "DriverKit only")
          Text("Output mode: \(modeLabel)")
            .font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Text("User-space device:").font(.caption).foregroundStyle(.secondary)
          Text(model.userSpaceVirtualDeviceEnabled ? "enabled" : "disabled").font(.caption)
          Spacer()
          Text(model.userSpaceVirtualDeviceStatus).font(.caption).foregroundStyle(
            model.userSpaceVirtualDeviceStatus.hasPrefix("error:") ? .orange : .secondary
          )
        }
        if let diag {
          if diag.hidGamepads.isEmpty {
            Text("No HID GamePad devices visible via IOKit.").font(.caption).foregroundStyle(
              .secondary
            )
          } else {
            VStack(spacing: 0) {
              ForEach(Array(diag.hidGamepads.enumerated()), id: \.element) { index, dev in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(dev.product ?? "GamePad").fontWeight(.medium)
                    Spacer()
                    if dev.isOJDDriverKit {
                      Text("OJD DriverKit").font(.caption2).foregroundStyle(.secondary)
                    } else if dev.isOJDUserSpace {
                      Text("OJD User-space").font(.caption2).foregroundStyle(.secondary)
                    }
                  }
                  HStack(spacing: 12) {
                    Text(String(format: "VID 0x%04X  PID 0x%04X", dev.vendorID, dev.productID))
                      .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Text("Transport: \(dev.transport ?? "unknown")").font(.caption).foregroundStyle(
                      .tertiary
                    )
                  }
                  HStack(spacing: 12) {
                    if let loc = dev.locationID {
                      Text("LocationID: \(loc)").font(.caption).foregroundStyle(.tertiary)
                    } else {
                      Text("LocationID: unknown").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text("IOUserClass: \(dev.ioUserClass ?? "unknown")").font(.caption)
                      .foregroundStyle(.tertiary)
                    Text("Serial: \(serialLabel(dev.serialKind))").font(.caption).foregroundStyle(
                      .tertiary
                    )
                  }
                }.padding(.vertical, 6)
              }
            }
          }
        } else {
          Text("Tap Refresh to query IOKit via daemon.").font(.caption).foregroundStyle(.secondary)
        }

        Divider().padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 6) {
          Text("Self-test: press buttons for 5 seconds.").font(.caption).foregroundStyle(.secondary)
          if let t = model.virtualDeviceSelfTest {
            VStack(alignment: .leading, spacing: 2) {
              Text(
                "DriverKit: value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)"
              ).font(.caption).foregroundStyle(.secondary)
              Text(
                "User-space: value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          HStack {
            SwiftUI.Button("Run Self-Test") {
              Task { await model.runVirtualDeviceSelfTest(seconds: 5) }
            }.buttonStyle(.bordered).disabled(!model.daemonConnected)
            Spacer()
          }
        }

        HStack {
          SwiftUI.Button {
            refreshingVirtualDevices = true
            Task {
              await model.refreshVirtualDeviceDiagnostics()
              refreshingVirtualDevices = false
            }
          } label: {
            Text(refreshingVirtualDevices ? "Refreshing…" : "Refresh")
          }.buttonStyle(.bordered).disabled(!model.daemonConnected || refreshingVirtualDevices)
          Spacer()
        }
      }
    } label: {
      Label("Virtual Devices", systemImage: "puzzlepiece.extension").fontWeight(.semibold)
    }
  }

  private func serialLabel(_ kind: XPCSerialKind) -> String {
    switch kind {
    case .none: return "none"
    case .ojdUserSpace: return "OJD"
    case .present: return "present"
    }
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
        "Daemon not running",
        detail: "Use Start Daemon in the Daemon Lifecycle card."
          + " Running with sudo puts the daemon in root's bootstrap namespace,"
          + " which breaks XPC communication."
      )
      tipRow(
        "No events in games",
        detail: "The target app must be focused."
          + " Events only dispatch to the active application."
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
      "Daemon: \(daemonStatusText)", "Input Monitoring: \(model.inputMonitoring)", "",
      "Controllers:",
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
    lines.append("")
    lines.append("User-space virtual device: \(model.userSpaceVirtualDeviceEnabled ? "enabled" : "disabled")")
    lines.append("User-space status: \(model.userSpaceVirtualDeviceStatus)")
    if let diag = model.virtualDeviceDiagnostics {
      lines.append("")
      lines.append("HID GamePad devices (IOKit): \(diag.hidGamepads.count)")
      lines.append("Output mode: \(diag.outputMode)")
      for d in diag.hidGamepads {
        let tag = d.isOJDDriverKit ? "OJD-DriverKit" : (d.isOJDUserSpace ? "OJD-UserSpace" : "other")
        lines.append(
          "  \(d.product ?? "GamePad")"
            + " — VID:0x" + String(format: "%04X", d.vendorID)
            + " PID:0x" + String(format: "%04X", d.productID)
            + " Transport:\(d.transport ?? "unknown")"
            + " IOUserClass:\(d.ioUserClass ?? "unknown")"
            + " Serial:\(serialLabel(d.serialKind))"
            + " [\(tag)]"
        )
      }
    }
    if let t = model.virtualDeviceSelfTest {
      lines.append("")
      lines.append("Virtual device self-test (\(t.seconds)s):")
      lines.append("  DriverKit: value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)")
      lines.append("  User-space: value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)")
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
  }
}
