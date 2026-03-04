import AppKit
import OpenJoystickDriverKit
import SwiftUI

private let captureRowLabelWidth: CGFloat = 110
/// Inner label width for key-name buttons. The bordered style adds ~12 pt per side,
/// giving a total button width of roughly captureKeyButtonWidth + 24 pt.
/// Setting it on the Text (not the outer button) is what forces identical widths.
private let captureKeyButtonWidth: CGFloat = 80

/// Optional decorative badge shown next to a button label.
enum ButtonBadge {
  /// Filled coloured circle with a letter (Xbox/DS4 face buttons).
  case xboxFace(_ letter: String, _ color: Color)
  /// Xbox logo glyph in Xbox green — Guide/Home button.
  case xboxLogo
  /// Short text on a tinted pill background (e.g. "LT", "RT").
  case textLabel(_ text: String)
  /// SF Symbol icon in secondary colour.
  case sfSymbol(_ name: String)
}

// MARK: - List row

struct KeyCaptureRow: View {
  let label: String
  let keyCode: UInt16
  let badge: ButtonBadge?
  let onCapture: (UInt16) -> Void

  @State private var capturing = false
  @State private var monitor: Any?

  init(
    label: String,
    keyCode: UInt16,
    badge: ButtonBadge? = nil,
    onCapture: @escaping (UInt16) -> Void
  ) {
    self.label = label
    self.keyCode = keyCode
    self.badge = badge
    self.onCapture = onCapture
  }

  var body: some View {
    HStack(spacing: 8) {
      BadgeView(badge: badge, size: 22)
      if !label.isEmpty {
        Text(label).lineLimit(1).frame(width: captureRowLabelWidth, alignment: .leading)
      }
      Spacer()
      SwiftUI.Button {
        startCapture()
      } label: {
        Text(capturing ? "Press any key\u{2026}" : KeyNames.name(for: keyCode)).lineLimit(1)
          .minimumScaleFactor(0.8).frame(width: captureKeyButtonWidth, alignment: .center)
      }.buttonStyle(.bordered).tint(capturing ? .accentColor : nil)
    }
  }

  private func startCapture() {
    capturing = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      onCapture(UInt16(event.keyCode))
      capturing = false
      if let mon = monitor {
        NSEvent.removeMonitor(mon)
        monitor = nil
      }
      return nil
    }
  }
}

// MARK: - Shared badge renderer

/// Renders a ButtonBadge at `size` points.
struct BadgeView: View {
  let badge: ButtonBadge?
  let size: CGFloat

  var body: some View {
    Group {
      if let badge {
        switch badge {
        case .xboxFace(let letter, let color): xboxFaceBadge(letter: letter, color: color)
        case .xboxLogo: xboxLogoBadge
        case .textLabel(let text): textLabelBadge(text: text)
        case .sfSymbol(let name): sfSymbolBadge(name: name)
        }
      } else {
        // Reserve the badge slot so key buttons stay right-aligned across all rows.
        Color.clear.frame(width: size, height: size)
      }
    }
  }

  private func xboxFaceBadge(letter: String, color: Color) -> some View {
    ZStack {
      Circle().fill(color)
      Text(letter).font(.system(size: size * 0.5, weight: .bold, design: .rounded)).foregroundStyle(
        .white
      )
    }.frame(width: size, height: size)
  }

  private var xboxLogoBadge: some View {
    Image(systemName: "xbox.logo").font(.system(size: size * 0.64)).foregroundStyle(
      Color(red: 0.13, green: 0.69, blue: 0.30)
    ).frame(width: size, height: size)
  }

  private func textLabelBadge(text: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.2).fill(Color.secondary.opacity(0.5)).frame(
        width: size,
        height: size * 0.68
      )
      Text(text).font(.system(size: size * 0.41, weight: .bold, design: .rounded)).foregroundStyle(
        .white
      )
    }.frame(width: size, height: size)
  }

  private func sfSymbolBadge(name: String) -> some View {
    Image(systemName: name).font(.system(size: size * 0.64)).foregroundStyle(.secondary).frame(
      width: size,
      height: size
    )
  }
}
