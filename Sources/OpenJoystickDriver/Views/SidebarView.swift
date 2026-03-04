import SwiftUI

struct SidebarView: View {
  @EnvironmentObject var model: AppModel
  @Binding var selection: SidebarItem?

  var body: some View {
    List(selection: $selection) {
      Section {
        if model.devices.isEmpty {
          Text("No controllers connected")
            .foregroundStyle(.secondary)
            .font(.caption)
        } else {
          ForEach(model.devices) { device in
            deviceRow(device)
              .tag(SidebarItem.device(device))
          }
        }
      } header: {
        Label("Devices", systemImage: "gamecontroller")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
      Section {
        Label("Permissions", systemImage: "lock.shield.fill")
          .tag(SidebarItem.permissions)
        Label("Diagnostics", systemImage: "stethoscope")
          .tag(SidebarItem.diagnostics)
      } header: {
        Label("System", systemImage: "gearshape")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
    }
    .listStyle(.sidebar)
  }

  private func deviceRow(_ device: DeviceViewModel) -> some View {
    HStack(spacing: 8) {
      Image(systemName: protocolIcon(for: device.parser))
        .foregroundStyle(protocolColor(for: device.parser))
        .imageScale(.medium)
      VStack(alignment: .leading, spacing: 2) {
        Text(device.name)
          .lineLimit(1)
        Text(device.parser)
          .font(.caption2)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(
            protocolColor(for: device.parser).opacity(0.15)
          )
          .foregroundStyle(protocolColor(for: device.parser))
          .clipShape(Capsule())
      }
    }
  }
}
