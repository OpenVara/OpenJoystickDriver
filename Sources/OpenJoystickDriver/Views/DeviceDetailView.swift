import SwiftUI

struct DeviceDetailView: View {
  let device: DeviceViewModel
  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      tabPicker
      if selectedTab == 0 {
        MappingEditorView(device: device)
      } else {
        infoTab
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: protocolIcon(for: device.parser))
        .font(.title)
        .foregroundStyle(protocolColor(for: device.parser))
      VStack(alignment: .leading, spacing: 4) {
        Text(device.name)
          .font(.title2)
          .fontWeight(.bold)
        HStack(spacing: 8) {
          vidPidChip(
            label: "VID",
            value: String(
              format: "0x%04X",
              device.vendorID
            )
          )
          vidPidChip(
            label: "PID",
            value: String(
              format: "0x%04X",
              device.productID
            )
          )
          parserBadge
        }
      }
      Spacer()
    }
    .padding()
  }

  private func vidPidChip(
    label: String,
    value: String
  ) -> some View {
    Text("\(label): \(value)")
      .font(.system(.caption, design: .monospaced))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.12))
      .foregroundStyle(.secondary)
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }

  private var parserBadge: some View {
    HStack(spacing: 3) {
      Image(
        systemName: protocolIcon(for: device.parser)
      )
      .imageScale(.small)
      Text(device.parser)
    }
    .font(.caption)
    .fontWeight(.medium)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      protocolColor(for: device.parser).opacity(0.15)
    )
    .foregroundStyle(protocolColor(for: device.parser))
    .clipShape(Capsule())
  }

  private var tabPicker: some View {
    Picker("Tab", selection: $selectedTab) {
      Text("Mapping").tag(0)
      Text("Info").tag(1)
    }
    .pickerStyle(.segmented)
    .padding()
  }

  private var infoTab: some View {
    Form {
      LabeledContent("Name", value: device.name)
      LabeledContent("Vendor ID") {
        Text(
          String(
            format: "0x%04X (%d)",
            device.vendorID,
            device.vendorID
          )
        )
      }
      LabeledContent("Product ID") {
        Text(
          String(
            format: "0x%04X (%d)",
            device.productID,
            device.productID
          )
        )
      }
      LabeledContent("Parser", value: device.parser)
      LabeledContent("Connection", value: "USB")
    }
    .formStyle(.grouped)
    .padding()
  }
}
