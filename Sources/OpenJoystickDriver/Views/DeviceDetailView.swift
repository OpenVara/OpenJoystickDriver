import SwiftUI

struct DeviceDetailView: View {
  let device: DeviceViewModel
  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      tabPicker
      if selectedTab == 0 { MappingEditorView(device: device) } else { infoTab }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(device.name).font(.largeTitle).fontWeight(.bold)
      HStack(spacing: 8) {
        Text(String(format: "VID: 0x%04X", device.vendorID)).font(.caption).foregroundStyle(
          .secondary
        )
        Text(String(format: "PID: 0x%04X", device.productID)).font(.caption).foregroundStyle(
          .secondary
        )
        Text(device.parser).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(
          .blue.opacity(0.15)
        ).foregroundStyle(.blue).clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }.padding()
  }

  private var tabPicker: some View {
    Picker("Tab", selection: $selectedTab) {
      Text("Mapping").tag(0)
      Text("Info").tag(1)
    }.pickerStyle(.segmented).padding()
  }

  private var infoTab: some View {
    Form {
      LabeledContent("Name", value: device.name)
      LabeledContent("Vendor ID") {
        Text(String(format: "0x%04X (%d)", device.vendorID, device.vendorID))
      }
      LabeledContent("Product ID") {
        Text(String(format: "0x%04X (%d)", device.productID, device.productID))
      }
      LabeledContent("Parser", value: device.parser)
      LabeledContent("Connection", value: "USB")
    }.formStyle(.grouped).padding()
  }
}
