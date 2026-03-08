import AppKit
import SwiftUI

struct PermissionsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !model.daemonConnected { daemonWarning }
        if model.daemonConnected && model.inputMonitoring.lowercased() != "granted" {
          rebuildNotice
        }
        daemonPathCard
        inputMonitoringCard
        virtualDeviceCard
      }.padding(.bottom, 52).padding()
    }.navigationTitle("Permissions")
  }

  private var inputMonitoringURL: String {
    "x-apple.systempreferences:" + "com.apple.preference.security" + "?Privacy_ListenEvent"
  }

  private var inputMonitoringCard: some View {
    PermissionCard(
      title: "Input Monitoring",
      systemImage: "keyboard",
      status: model.inputMonitoring,
      description: "Required to read controller input from USB and HID devices.",
      settingsURL: inputMonitoringURL,
      showHint: model.inputMonitoring.lowercased() != "granted"
    ).padding(.horizontal)
  }

  private var daemonWarning: some View {
    GroupBox {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.title3)
        VStack(alignment: .leading, spacing: 2) {
          Text("Daemon not connected").fontWeight(.semibold)
          Text(
            "Start daemon from Diagnostics tab." + " Permission states shown below"
              + " may not reflect daemon process."
          ).font(.caption).foregroundStyle(.secondary)
        }
      }
    }.padding(.horizontal)
  }

  private var rebuildNotice: some View {
    GroupBox {
      HStack(spacing: 8) {
        Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(.orange).font(
          .title3
        )
        VStack(alignment: .leading, spacing: 2) {
          Text("Permissions reset after rebuild").fontWeight(.semibold)
          Text(
            "Daemon binary changed - re-grant Input Monitoring above, then restart daemon."
          ).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        SwiftUI.Button("Restart Daemon") { Task { await model.restartDaemon() } }.buttonStyle(
          .bordered
        )
      }
    }.padding(.horizontal)
  }

  private var virtualDeviceCard: some View {
    let ext = model.extensionManager
    return GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: "gamecontroller").font(.title3).frame(width: 24)
          Text("Virtual HID Gamepad (DriverKit)").fontWeight(.semibold)
          Spacer()
          PermissionStatusIcon(isGranted: ext.installState.isInstalled)
        }
        Text(
          "DriverKit extension that exposes a virtual gamepad to SDL3, GCController, and "
            + "any HID-aware app — no Accessibility permission required."
        ).font(.caption).foregroundStyle(.secondary)
        Text(ext.installState.label)
          .font(.caption)
          .foregroundStyle(
            ext.installState.isInstalled
              ? .green
              : (ext.installState.isPending ? .orange : .secondary)
          )
        if ext.installState == .requiresApproval {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).imageScale(
              .small
            )
            Text("Open System Settings → Privacy & Security to approve the extension.").font(
              .caption
            ).foregroundStyle(.secondary)
          }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(
            Color.orange.opacity(0.08)
          ).clipShape(RoundedRectangle(cornerRadius: 6))
        }
        HStack(spacing: 8) {
          SwiftUI.Button("Install Extension") {
            ext.installExtension()
          }.buttonStyle(.bordered).disabled(
            ext.installState.isInstalled || ext.installState.isPending
          )
          if ext.installState.isInstalled {
            SwiftUI.Button("Remove") {
              ext.uninstallExtension()
            }.buttonStyle(.bordered).foregroundStyle(.red)
          }
        }
      }
    } label: {
      Label("Virtual Device Extension", systemImage: "puzzlepiece.extension").fontWeight(.semibold)
    }.padding(.horizontal)
  }

  private var daemonPathCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        if let path = model.daemonExecutablePath {
          Text(path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
          Text("Not found").font(.caption).foregroundStyle(.secondary)
        }
        Text("Grant permissions to this binary. Permissions reset after each rebuild.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } label: {
      Label("Daemon Binary", systemImage: "terminal").fontWeight(.semibold)
    }.padding(.horizontal)
  }
}

private struct PermissionCard: View {
  let title: String
  let systemImage: String
  let status: String
  let description: String
  let settingsURL: String
  var showHint: Bool = false

  private var isGranted: Bool { status.lowercased() == "granted" }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: systemImage).font(.title3).frame(width: 24)
          Text(title).fontWeight(.semibold)
          Spacer()
          PermissionStatusIcon(isGranted: isGranted)
        }
        Text(description).font(.caption).foregroundStyle(.secondary)
        if showHint { hintBox }
        SwiftUI.Button("Open System Settings") {
          if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
        }.buttonStyle(.bordered)
      }
    }
  }

  private var hintBox: some View {
    HStack(spacing: 6) {
      Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).imageScale(.small)
      Text("Grant access, then restart daemon" + " from Diagnostics.").font(.caption)
        .foregroundStyle(.secondary)
    }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(
      Color.yellow.opacity(0.08)
    ).clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
