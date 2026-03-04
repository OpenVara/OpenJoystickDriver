import OpenJoystickDriverKit
import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
  case devices, permissions, diagnostics

  var label: String {
    switch self {
    case .devices: return "Devices"
    case .permissions: return "Permissions"
    case .diagnostics: return "Diagnostics"
    }
  }

  var systemImage: String {
    switch self {
    case .devices: return "gamecontroller.fill"
    case .permissions: return "lock.shield.fill"
    case .diagnostics: return "stethoscope"
    }
  }
}

struct ContentView: View {
  @EnvironmentObject var model: AppModel
  @State private var selectedTab: AppTab = .devices
  @State private var selectedDevice: DeviceViewModel?

  var body: some View {
    VStack(spacing: 0) {
      tabBar
      Divider()
      contentArea
      Divider()
      StatusFooter().environmentObject(model)
    }.onChange(of: model.devices) { newDevices in
      if let sel = selectedDevice, !newDevices.contains(sel) { selectedDevice = newDevices.first }
      if selectedDevice == nil { selectedDevice = newDevices.first }
    }
  }

  private var tabBar: some View {
    HStack(spacing: 0) { ForEach(AppTab.allCases, id: \.rawValue) { tab in appTab(tab) } }
      .background(.bar).frame(maxWidth: .infinity)
  }

  private func appTab(_ tab: AppTab) -> some View {
    let isActive = selectedTab == tab
    return Button {
      selectedTab = tab
    } label: {
      VStack(spacing: 4) {
        Image(systemName: tab.systemImage).font(
          .system(size: 17, weight: isActive ? .semibold : .regular)
        )
        Text(tab.label).font(.caption).fontWeight(isActive ? .semibold : .regular)
      }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(
        isActive ? Color.accentColor : Color.secondary
      ).overlay(alignment: .top) {
        if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
  }

  @ViewBuilder private var contentArea: some View {
    switch selectedTab {
    case .devices: devicesContent
    case .permissions: PermissionsView()
    case .diagnostics: DiagnosticsView()
    }
  }

  private var devicesContent: some View {
    NavigationSplitView {
      deviceSidebar.navigationSplitViewColumnWidth(min: 160, ideal: 200)
    } detail: {
      deviceDetail
    }
  }

  @ViewBuilder private var deviceSidebar: some View {
    if model.devices.isEmpty {
      VStack(spacing: 10) {
        Image(systemName: "gamecontroller").font(.system(size: 32)).foregroundStyle(.tertiary)
        Text("No controllers").font(.callout).foregroundStyle(.secondary)
        Text("Connect a USB controller.").font(.caption).foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(model.devices, selection: $selectedDevice) { device in deviceRow(device).tag(device) }
        .listStyle(.sidebar)
    }
  }

  @ViewBuilder private var deviceDetail: some View {
    if let device = selectedDevice {
      DeviceDetailView(device: device).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "arrow.left").font(.title3).foregroundStyle(.tertiary)
        Text("Select a controller").font(.callout).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func deviceRow(_ device: DeviceViewModel) -> some View {
    HStack(spacing: 10) {
      Image(systemName: protocolIcon(for: device.parser)).font(.title3).foregroundStyle(
        protocolColor(for: device.parser)
      ).frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(device.name).lineLimit(1).fontWeight(.medium)
        HStack(spacing: 4) {
          Text(device.parser).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
            .background(protocolColor(for: device.parser).opacity(0.15)).foregroundStyle(
              protocolColor(for: device.parser)
            ).clipShape(Capsule())
          Text(device.connection).font(.caption2).foregroundStyle(.tertiary)
        }
      }
    }.padding(.vertical, 2).contentShape(Rectangle())
  }
}
