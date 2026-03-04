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

  @State private var showInputMonitor = true
  @State private var inputState: DeviceInputState?
  @State private var packets: [PacketLogEntry] = []
  @State private var clearOffset: Int = 0
  @State private var isCapturing = false
  @State private var captureError: String?
  @State private var captureStartTime: TimeInterval = 0
  @State private var filterDirection: PacketFilter = .all
  @State private var autoScroll = true

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        inputMonitorCard
        packetLogCard
      }.padding(.horizontal).padding(.top).padding(.bottom, 52)
    }.task { await pollInputState() }.task { await pollPacketLog() }.onDisappear {
      if isCapturing { stopCapture() }
    }
  }

  // MARK: - Input monitor

  private var inputMonitorCard: some View {
    GroupBox {
      if showInputMonitor {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 20) {
            StickVisualizer(
              x: inputState?.leftStickX ?? 0,
              y: inputState?.leftStickY ?? 0,
              label: "L"
            )
            StickVisualizer(
              x: inputState?.rightStickX ?? 0,
              y: inputState?.rightStickY ?? 0,
              label: "R"
            )
            VStack(alignment: .leading, spacing: 6) {
              TriggerBar(value: inputState?.leftTrigger ?? 0, label: "LT")
              TriggerBar(value: inputState?.rightTrigger ?? 0, label: "RT")
              Divider().padding(.vertical, 2)
              pressedButtonsView
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    } label: {
      Button {
        showInputMonitor.toggle()
      } label: {
        HStack {
          Label("Input Monitor", systemImage: "gamecontroller").fontWeight(.semibold)
          Spacer()
          Image(systemName: showInputMonitor ? "chevron.up" : "chevron.down").font(.caption2)
            .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
  }

  @ViewBuilder private var pressedButtonsView: some View {
    let pressed = inputState?.pressedButtons ?? []
    if pressed.isEmpty {
      Text("No buttons pressed").font(.caption2).foregroundStyle(.tertiary)
    } else {
      FlowLayout(spacing: 4) {
        ForEach(pressed, id: \.self) { btn in
          Text(btn).font(.system(.caption2, design: .monospaced)).padding(.horizontal, 5).padding(
            .vertical,
            2
          ).background(Color.accentColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
        }
      }
    }
  }

  // MARK: - Packet log

  private var visiblePackets: [PacketLogEntry] {
    let base = packets.dropFirst(clearOffset)
    switch filterDirection {
    case .all: return Array(base.suffix(200))
    case .rx: return Array(base.filter { $0.direction.uppercased() == "RX" }.suffix(200))
    case .tx: return Array(base.filter { $0.direction.uppercased() == "TX" }.suffix(200))
    }
  }

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

  private func packetRow(entry: PacketLogEntry, firstTimestamp: TimeInterval) -> some View {
    let relative = entry.timestamp - firstTimestamp
    let isRX = entry.direction.uppercased() == "RX"
    return HStack(spacing: 6) {
      Text(String(format: "+%.3fs", relative)).frame(width: 68, alignment: .trailing)
        .foregroundStyle(.secondary)
      Text(entry.direction.uppercased()).frame(width: 22, alignment: .leading).fontWeight(.semibold)
        .foregroundStyle(isRX ? Color.green : Color.orange)
      Text(gipCommandName(from: entry.hex)).frame(width: 78, alignment: .leading).foregroundStyle(
        .primary
      )
      Text(entry.hex).foregroundStyle(.secondary).textSelection(.enabled)
      Spacer(minLength: 0)
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.hex, forType: .string)
      } label: {
        Image(systemName: "doc.on.doc")
      }.buttonStyle(.plain).foregroundStyle(.tertiary).help("Copy hex")
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

  // MARK: - Capture

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

  private func pollInputState() async {
    while !Task.isCancelled {
      if showInputMonitor, model.daemonConnected {
        let new = await model.deviceInputState(
          vendorID: device.vendorID,
          productID: device.productID
        )
        // Only push to SwiftUI when the value actually changed to avoid spurious redraws.
        if new != inputState { withAnimation(.none) { inputState = new } }
      }
      // 10 Hz when visible, back off to 2 Hz when collapsed - XPC round-trips are expensive.
      try? await Task.sleep(for: .milliseconds(showInputMonitor ? 100 : 500))
    }
  }

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

// MARK: - Stick visualizer

private struct StickVisualizer: View {
  let x: Float
  let y: Float
  let label: String

  private let size: CGFloat = 80
  private let dotRadius: CGFloat = 5
  private let deadzone: Float = 0.15

  /// Maximum travel of the dot centre from the circle centre.
  private var travel: CGFloat { size / 2 - dotRadius - 3 }

  /// Snaps to zero when inside deadzone so the dot sits exactly at centre
  /// rather than wobbling with sub-deadzone drift.
  private var cx: CGFloat { abs(x) > deadzone ? CGFloat(max(-1, min(1, x))) : 0 }
  /// GIPParser convention: negative y = physical up, which already aligns with
  /// SwiftUI where negative offset-y moves a view upward. No flip needed.
  private var cy: CGFloat { abs(y) > deadzone ? CGFloat(max(-1, min(1, y))) : 0 }

  private var isActive: Bool { abs(x) > deadzone || abs(y) > deadzone }

  var body: some View {
    VStack(spacing: 4) {
      Text(label).font(.system(.caption2, design: .monospaced).weight(.medium)).foregroundStyle(
        .secondary
      )

      ZStack {
        // Background fill
        Circle().fill(Color(nsColor: .controlBackgroundColor))
        // Boundary ring
        Circle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        // Crosshair - stops short of the edge to feel less cluttered
        let pad: CGFloat = 10
        Path { p in
          p.move(to: CGPoint(x: size / 2, y: pad))
          p.addLine(to: CGPoint(x: size / 2, y: size - pad))
          p.move(to: CGPoint(x: pad, y: size / 2))
          p.addLine(to: CGPoint(x: size - pad, y: size / 2))
        }.stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        // Position dot
        Circle().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.4)).frame(
          width: dotRadius * 2,
          height: dotRadius * 2
        ).offset(x: cx * travel, y: cy * travel)
      }.frame(width: size, height: size)

      // Axis readout - values light up when outside deadzone
      HStack(spacing: 6) {
        axisValue("X", value: x)
        axisValue("Y", value: y)
      }
    }
  }

  private func axisValue(_ name: String, value: Float) -> some View {
    HStack(spacing: 2) {
      Text(name).foregroundStyle(.quaternary)
      Text(String(format: "%+.2f", value)).foregroundStyle(
        abs(value) > deadzone ? Color.primary : Color.secondary
      )
    }.font(.system(.caption2, design: .monospaced))
  }
}

// MARK: - Trigger bar

private struct TriggerBar: View {
  let value: Float
  let label: String

  var body: some View {
    HStack(spacing: 6) {
      Text(label).font(.system(.caption2, design: .monospaced).weight(.medium)).foregroundStyle(
        .secondary
      ).frame(width: 20, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.1))
          RoundedRectangle(cornerRadius: 2).fill(
            Color.accentColor.opacity(value > 0.05 ? 0.8 : 0.3)
          ).frame(width: max(0, geo.size.width * CGFloat(value)))
        }
      }.frame(height: 6)
      Text(String(format: "%.2f", value)).font(.system(.caption2, design: .monospaced))
        .foregroundStyle(value > 0.05 ? Color.primary : Color.secondary).frame(
          width: 32,
          alignment: .trailing
        )
    }
  }
}

// MARK: - Flow layout (wrapping HStack for button chips)

private struct FlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        y += rowHeight + spacing
        x = 0
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: maxWidth, height: y + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        y += rowHeight + spacing
        x = bounds.minX
        rowHeight = 0
      }
      sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
