import SwiftUI

struct SidebarView: View {
  @EnvironmentObject var model: AppModel
  @Binding var selection: SidebarItem?

  var body: some View {
    List(selection: $selection) {
      Section("Devices") {
        if model.devices.isEmpty {
          Text("No controllers connected").foregroundStyle(.secondary).font(.caption)
        } else {
          ForEach(model.devices) { device in
            Label(device.name, systemImage: "gamecontroller.fill").tag(SidebarItem.device(device))
          }
        }
      }
      Section("System") {
        Label("Permissions", systemImage: "lock.shield.fill").tag(SidebarItem.permissions)
        Label("Diagnostics", systemImage: "stethoscope").tag(SidebarItem.diagnostics)
      }
    }.toolbar {
      ToolbarItem(placement: .automatic) {
        HStack(spacing: 4) {
          StatusBadge(status: model.daemonConnected ? .ok : .error)
          Text(model.daemonConnected ? "Daemon" : "No Daemon").font(.caption).foregroundStyle(
            .secondary
          )
        }
      }
    }
  }
}
