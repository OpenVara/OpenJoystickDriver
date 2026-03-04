import AppKit
import SwiftUI

struct PermissionsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !model.daemonConnected { daemonWarning }

        PermissionCard(
          title: "Input Monitoring",
          systemImage: "keyboard",
          status: model.inputMonitoring,
          description: "Required to monitor keyboard" + " state and detect conflicts.",
          settingsURL: "x-apple.systempreferences:" + "com.apple.preference.security"
            + "?Privacy_ListenEvent"
        ).padding(.horizontal)

        PermissionCard(
          title: "Accessibility",
          systemImage: "accessibility",
          status: model.accessibility,
          description: "Required to post CGEvents" + " (keyboard/mouse output) to system.",
          settingsURL: "x-apple.systempreferences:" + "com.apple.preference.security"
            + "?Privacy_Accessibility"
        ).padding(.horizontal)
      }.padding(.vertical)
    }.navigationTitle("Permissions")
  }

  private var daemonWarning: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
      Text("Daemon not running \u{2014} start it from Diagnostics tab.").font(.callout)
    }.padding().background(.yellow.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal)
  }
}

private struct PermissionCard: View {
  let title: String
  let systemImage: String
  let status: String
  let description: String
  let settingsURL: String

  private var badgeStatus: BadgeStatus {
    switch status.lowercased() {
    case "granted": .ok
    case "denied", "notdetermined": .error
    default: .unknown
    }
  }

  private var statusLabel: String {
    switch status.lowercased() {
    case "granted": "Granted"
    case "denied": "Denied"
    case "notdetermined": "Not Determined"
    default: status
    }
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: systemImage).frame(width: 20)
          Text(title).fontWeight(.semibold)
          Spacer()
          StatusBadge(status: badgeStatus)
          Text(statusLabel).foregroundStyle(badgeStatus == .ok ? .green : .red).font(.subheadline)
        }
        Text(description).font(.caption).foregroundStyle(.secondary)
        SwiftUI.Button("Open System Settings") {
          if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
        }.buttonStyle(.bordered)
      }
    }
  }
}
