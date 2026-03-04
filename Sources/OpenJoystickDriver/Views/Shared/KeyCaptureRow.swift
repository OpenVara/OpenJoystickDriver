import AppKit
import SwiftUI

private let captureRowLabelWidth: CGFloat = 130

struct KeyCaptureRow: View {
  let label: String
  let keyCode: UInt16
  let onCapture: (UInt16) -> Void

  @State private var capturing = false
  @State private var monitor: Any?

  var body: some View {
    HStack {
      Text(label).frame(width: captureRowLabelWidth, alignment: .leading)
      Spacer()
      SwiftUI.Button(capturing ? "Press any key\u{2026}" : KeyNames.name(for: keyCode)) {
        startCapture()
      }.buttonStyle(.bordered).tint(capturing ? .accentColor : nil)
    }
  }

  private func startCapture() {
    capturing = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      onCapture(UInt16(event.keyCode))
      capturing = false
      if let currentMonitor = monitor {
        NSEvent.removeMonitor(currentMonitor)
        monitor = nil
      }
      return nil
    }
  }
}
