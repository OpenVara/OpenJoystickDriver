import SwiftUI

enum BadgeStatus { case ok, warning, error, unknown }

struct StatusBadge: View {
  let status: BadgeStatus

  var body: some View { Circle().fill(color).frame(width: 8, height: 8) }

  private var color: Color {
    switch status {
    case .ok: .green
    case .warning: .yellow
    case .error: .red
    case .unknown: .secondary
    }
  }
}
