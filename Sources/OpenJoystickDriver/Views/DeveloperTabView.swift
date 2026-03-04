import OpenJoystickDriverKit
import SwiftUI

private enum PacketFilter: String, CaseIterable {
  case all = "All"
  case rx = "RX"
  case tx = "TX"
}

// swiftlint:disable file_length
struct DeveloperTabView: View {
  let device: DeviceViewModel
  @EnvironmentObject var model: AppModel
  @State private var packets: [PacketLogEntry] = []
  @State private var clearOffset: Int = 0
  @State private var isCapturing = false
  @State private var captureError: String?
  @State private var captureStartTime: TimeInterval = 0
  @State private var filterDirection: PacketFilter = .all
  @State private var autoScroll = true

  var body: some View {
    packetLogCard.padding(.horizontal).padding(.top).padding(.bottom, 16).frame(
      maxHeight: .infinity,
      alignment: .top
    ).task { await pollPacketLog() }.onDisappear { if isCapturing { stopCapture() } }
  }

  // MARK: - Derived state

  private var visiblePackets: [PacketLogEntry] {
    let base = packets.dropFirst(clearOffset)
    switch filterDirection {
    case .all: return Array(base.suffix(200))
    case .rx: return Array(base.filter { $0.direction.uppercased() == "RX" }.suffix(200))
    case .tx: return Array(base.filter { $0.direction.uppercased() == "TX" }.suffix(200))
    }
  }

  // MARK: - Packet log card

  private var packetLogCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        controlsRow
        if let err = captureError { Text(err).font(.caption).foregroundStyle(.orange) }
        packetListView
      }
    } label: {
      Label("Packet Log", systemImage: "dot.scope").fontWeight(.semibold)
    }
  }

  private var controlsRow: some View {
    HStack(spacing: 8) {
      if isCapturing {
        Button(role: .destructive) {
          stopCapture()
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }.buttonStyle(.bordered)
      } else {
        Button {
          startCapture()
        } label: {
          Label("Capture", systemImage: "record.circle")
        }.buttonStyle(.bordered).tint(.green)
      }

      Text("\(visiblePackets.count) pkts").font(.caption).foregroundStyle(.secondary)
        .monospacedDigit()

      Spacer()

      Picker("", selection: $filterDirection) {
        ForEach(PacketFilter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
      }.pickerStyle(.segmented).labelsHidden().frame(width: 110)

      Toggle("↓", isOn: $autoScroll).toggleStyle(.checkbox).help("Auto-scroll to newest packet")
        .font(.caption)

      if !packets.isEmpty {
        Button("Clear") {
          packets = []
          clearOffset = 0
        }.buttonStyle(.plain).font(.caption)
      }
    }
  }

  @ViewBuilder private var packetListView: some View {
    if visiblePackets.isEmpty {
      emptyStateText.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 1) {
            let firstTs = captureStartTime
            ForEach(visiblePackets, id: \.timestamp) { entry in
              packetRow(entry: entry, firstTimestamp: firstTs).id(entry.timestamp)
            }
          }.padding(.horizontal, 4).padding(.vertical, 2)
        }.frame(maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor)).clipShape(
          RoundedRectangle(cornerRadius: 6)
        ).onChange(of: visiblePackets.count) { _ in
          guard autoScroll, let last = visiblePackets.last else { return }
          proxy.scrollTo(last.timestamp, anchor: .bottom)
        }
      }
    }
  }

  @ViewBuilder private var emptyStateText: some View {
    if isCapturing {
      Text("Waiting for packets\u{2026}").font(.caption).foregroundStyle(.secondary)
    } else if !packets.isEmpty {
      Text("All packets filtered. Change the filter or press Clear.").font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Text("Press Capture to record raw USB/HID packets.").font(.caption).foregroundStyle(
        .secondary
      )
    }
  }

  // MARK: - Packet row

  private func packetRow(entry: PacketLogEntry, firstTimestamp: TimeInterval) -> some View {
    let relative = entry.timestamp - firstTimestamp
    let relStr = String(format: "+%.3fs", relative)
    let isRX = entry.direction.uppercased() == "RX"
    let cmd = gipCommandName(from: entry.hex)
    return HStack(spacing: 6) {
      Text(relStr).frame(width: 68, alignment: .trailing).foregroundStyle(.secondary)
      Text(entry.direction.uppercased()).frame(width: 22, alignment: .leading).fontWeight(.semibold)
        .foregroundStyle(isRX ? Color.green : Color.orange)
      Text(cmd).frame(width: 78, alignment: .leading).foregroundStyle(.primary)
      Text(entry.hex).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
    }.font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 1)
  }

  private func gipCommandName(from hex: String) -> String {
    guard let first = hex.split(separator: " ").first, let cmd = UInt8(first, radix: 16) else {
      return "???"
    }
    switch cmd {
    case 0x01: return "ANNOUNCE"
    case 0x02: return "STATUS"
    case 0x03: return "KEEPALIVE"
    case 0x04: return "RECONNECT"
    case 0x05: return "POWER"
    case 0x06: return "AUTH"
    case 0x07: return "VKEY"
    case 0x09: return "RUMBLE"
    case 0x0A: return "LED"
    case 0x20: return "INPUT"
    default: return "0x\(String(cmd, radix: 16, uppercase: true))"
    }
  }

  // MARK: - Capture control

  private func startCapture() {
    packets = []
    clearOffset = 0
    captureError = nil
    captureStartTime = Date().timeIntervalSince1970
    isCapturing = true
    Task { await model.setSuppressOutput(true) }
  }

  private func stopCapture() {
    isCapturing = false
    Task { await model.setSuppressOutput(false) }
  }

  // MARK: - Polling

  private func pollPacketLog() async {
    while !Task.isCancelled {
      guard isCapturing else {
        try? await Task.sleep(for: .milliseconds(200))
        continue
      }
      guard model.daemonConnected else {
        captureError = "Daemon not connected \u{2014} cannot capture packets."
        stopCapture()
        continue
      }
      let log = await model.packetLog(vendorID: device.vendorID, productID: device.productID)
      let newEntries = log.filter { $0.timestamp >= captureStartTime }
      if newEntries.count > packets.count { packets = newEntries }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }
}
