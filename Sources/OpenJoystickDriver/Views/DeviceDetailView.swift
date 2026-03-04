import OpenJoystickDriverKit
import SwiftUI

struct DeviceDetailView: View {
  let device: DeviceViewModel
  @EnvironmentObject var model: AppModel
  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerSection
      Divider()
      if selectedTab == 0 {
        MappingEditorView(device: device)
      } else if selectedTab == 2 {
        DeveloperTabView(device: device)
      } else {
        infoTab
      }
    }.onChange(of: model.developerMode) { newValue in
      if !newValue && selectedTab == 2 { selectedTab = 0 }
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: protocolIcon(for: device.parser)).font(.title).foregroundStyle(
          protocolColor(for: device.parser)
        )
        VStack(alignment: .leading, spacing: 4) {
          Text(device.name).font(.title2).fontWeight(.bold)
          HStack(spacing: 8) {
            vidPidChip(label: "VID", value: String(format: "0x%04X", device.vendorID))
            vidPidChip(label: "PID", value: String(format: "0x%04X", device.productID))
            parserBadge
          }
        }
        Spacer()
      }.padding()
      detailTabBar
    }.background(.bar)
  }

  private var detailTabs: [(label: String, icon: String, tag: Int)] {
    var tabs = [
      (label: "Mapping", icon: "slider.horizontal.3", tag: 0),
      (label: "Info", icon: "info.circle", tag: 1),
    ]
    if model.developerMode { tabs.append((label: "Developer", icon: "hammer", tag: 2)) }
    return tabs
  }

  private var detailTabBar: some View {
    HStack(spacing: 0) {
      ForEach(detailTabs, id: \.tag) { tab in
        detailTabButton(label: tab.label, icon: tab.icon, tag: tab.tag)
      }
    }.background(.bar).frame(maxWidth: .infinity)
  }

  private func detailTabButton(label: String, icon: String, tag: Int) -> some View {
    let isActive = selectedTab == tag
    return Button {
      selectedTab = tag
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 17, weight: isActive ? .semibold : .regular))
        Text(label).font(.caption).fontWeight(isActive ? .semibold : .regular)
      }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(
        isActive ? Color.accentColor : Color.secondary
      ).overlay(alignment: .top) {
        if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
  }

  private func vidPidChip(label: String, value: String) -> some View {
    Text("\(label): \(value)").font(.system(.caption, design: .monospaced)).padding(.horizontal, 6)
      .padding(.vertical, 2).background(Color.secondary.opacity(0.12)).foregroundStyle(.secondary)
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }

  private var parserBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: protocolIcon(for: device.parser)).imageScale(.small)
      Text(device.parser)
    }.font(.caption).fontWeight(.medium).padding(.horizontal, 8).padding(.vertical, 3).background(
      protocolColor(for: device.parser).opacity(0.15)
    ).foregroundStyle(protocolColor(for: device.parser)).clipShape(Capsule())
  }

  private var infoTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        deviceSection
        identifiersSection
        driverSection
      }.padding()
    }
  }

  private var deviceSection: some View {
    GroupBox {
      VStack(spacing: 0) {
        infoRow(label: "Name", value: device.name)
        Divider()
        infoRow(label: "Serial Number", value: device.serialNumber ?? "Not available")
        Divider()
        infoRow(label: "Connection", value: connectionDescription)
      }
    } label: {
      Label("Device", systemImage: "gamecontroller").fontWeight(.semibold)
    }
  }

  private var identifiersSection: some View {
    GroupBox {
      VStack(spacing: 0) {
        infoRow(
          label: "Vendor ID",
          value: String(format: "0x%04X  (%d)", device.vendorID, device.vendorID)
        )
        Divider()
        infoRow(
          label: "Product ID",
          value: String(format: "0x%04X  (%d)", device.productID, device.productID)
        )
      }
    } label: {
      Label("USB Identifiers", systemImage: "number").fontWeight(.semibold)
    }
  }

  private var driverSection: some View {
    GroupBox {
      infoRow(label: "Protocol", value: parserFullName)
    } label: {
      Label("Driver", systemImage: "cpu").fontWeight(.semibold)
    }
  }

  private var connectionDescription: String {
    switch device.connection {
    case "HID": return "IOKit HID (Class 0x03)"
    default: return "USB Vendor-Specific (Class 0xFF)"
    }
  }

  private var parserFullName: String {
    switch device.parser.uppercased() {
    case "GIP": return "GIP - Xbox Gaming Input Protocol"
    case "DS4": return "DS4 - DualShock 4"
    default: return device.parser
    }
  }

  private func infoRow(label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
      Text(value).foregroundStyle(.primary).textSelection(.enabled).multilineTextAlignment(.leading)
      Spacer()
    }.padding(.vertical, 6)
  }
}
