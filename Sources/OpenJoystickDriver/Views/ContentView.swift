import OpenJoystickDriverKit
import SwiftUI

enum SidebarItem: Hashable {
  case device(DeviceViewModel)
  case permissions
  case diagnostics
}

struct ContentView: View {
  @EnvironmentObject var model: AppModel
  @State private var selection: SidebarItem? = .permissions

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $selection)
    } detail: {
      detailView
    }.navigationSplitViewStyle(.balanced)
  }

  @ViewBuilder private var detailView: some View {
    switch selection {
    case .device(let device): DeviceDetailView(device: device)
    case .permissions: PermissionsView()
    case .diagnostics: DiagnosticsView()
    case nil: Text("Select item").foregroundStyle(.secondary)
    }
  }
}
