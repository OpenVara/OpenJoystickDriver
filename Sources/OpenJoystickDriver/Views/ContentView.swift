import OpenJoystickDriverKit
import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
  case permissions, diagnostics

  var label: String {
    switch self {
    case .permissions: return "Permissions"
    case .diagnostics: return "Diagnostics"
    }
  }

  var systemImage: String {
    switch self {
    case .permissions: return "lock.shield.fill"
    case .diagnostics: return "stethoscope"
    }
  }
}

struct ContentView: View {
  @EnvironmentObject var model: AppModel
  @State private var selectedTab: AppTab = .diagnostics

  var body: some View {
    VStack(spacing: 0) {
      tabBar
      Divider()
      contentArea
      Divider()
      StatusFooter().environmentObject(model)
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
    case .permissions: PermissionsView()
    case .diagnostics: DiagnosticsView()
    }
  }
}
