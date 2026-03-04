import SwiftUI

struct StatusFooter: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    HStack(spacing: 12) {
      daemonIndicator
      Divider().frame(height: 12)
      permissionIndicator(
        "Input Monitoring",
        systemImage: "keyboard",
        status: model.inputMonitoring
      )
      permissionIndicator(
        "Accessibility",
        systemImage: "accessibility",
        status: model.accessibility
      )
      Spacer()
      deviceCount
    }.padding(.horizontal, 12).padding(.vertical, 6).background(.bar).font(.caption)
  }

  private var daemonIndicator: some View {
    HStack(spacing: 4) {
      Circle().fill(model.daemonConnected ? .green : .red).frame(width: 7, height: 7)
      Text(model.daemonConnected ? "Daemon" : "No Daemon").foregroundStyle(.secondary)
    }
  }

  private func permissionIndicator(_ label: String, systemImage: String, status: String)
    -> some View
  {
    HStack(spacing: 3) {
      Image(systemName: systemImage).foregroundStyle(.secondary).imageScale(.small)
      Image(
        systemName: status.lowercased() == "granted" ? "checkmark.circle.fill" : "xmark.circle.fill"
      ).foregroundStyle(status.lowercased() == "granted" ? .green : .red).imageScale(.small)
    }.help("\(label): \(status.capitalized)")
  }

  private var deviceCount: some View {
    HStack(spacing: 3) {
      Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary).imageScale(.small)
      Text("\(model.devices.count)").foregroundStyle(.secondary)
    }
  }
}
