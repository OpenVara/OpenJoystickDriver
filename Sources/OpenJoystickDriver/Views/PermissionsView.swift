import AppKit
import SwiftUI

struct PermissionsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !model.daemonConnected { daemonWarning }
        if model.daemonConnected
          && (model.inputMonitoring.lowercased() != "granted"
            || model.accessibility.lowercased() != "granted")
        {
          rebuildNotice
        }
        daemonPathCard
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          PermissionCard(
            title: "Input Monitoring",
            systemImage: "keyboard",
            status: model.inputMonitoring,
            description: "Required to monitor keyboard" + " state and detect conflicts.",
            settingsURL: inputMonitoringURL,
            showHint: model.inputMonitoring.lowercased() != "granted"
          )
          PermissionCard(
            title: "Accessibility",
            systemImage: "accessibility",
            status: model.accessibility,
            description: "Required to post CGEvents" + " (keyboard/mouse output) to system.",
            settingsURL: accessibilityURL,
            showHint: model.accessibility.lowercased() != "granted"
          )
        }.padding(.horizontal)
      }.padding()
    }.navigationTitle("Permissions")
  }

  private var inputMonitoringURL: String {
    "x-apple.systempreferences:" + "com.apple.preference.security" + "?Privacy_ListenEvent"
  }

  private var accessibilityURL: String {
    "x-apple.systempreferences:" + "com.apple.preference.security" + "?Privacy_Accessibility"
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
            "Daemon binary changed - re-grant denied" + " permissions above, then restart daemon."
          ).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        SwiftUI.Button("Restart Daemon") { Task { await model.restartDaemon() } }.buttonStyle(
          .bordered
        )
      }
    }.padding(.horizontal)
  }

  private var daemonPathCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        if let path = model.daemonExecutablePath {
          Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(6)
            .frame(maxWidth: .infinity, alignment: .leading).background(
              Color(nsColor: .textBackgroundColor).opacity(0.5)
            ).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
          Text("Not found").font(.caption).foregroundStyle(.secondary)
        }
        Text(
          "Grant permissions to this binary in System Settings. Permissions reset after each rebuild."
        ).font(.caption).foregroundStyle(.secondary)
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
