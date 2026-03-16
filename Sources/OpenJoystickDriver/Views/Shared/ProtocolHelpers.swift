import SwiftUI

func protocolIcon(for parser: String) -> String {
  switch parser.uppercased() {
  case "GIP": return "xbox.logo"
  case "DS4": return "playstation.logo"
  default: return "gamecontroller.fill"
  }
}

func protocolColor(for parser: String) -> Color {
  switch parser.uppercased() {
  case "GIP": return Color(red: 0.13, green: 0.69, blue: 0.30)
  case "DS4": return .blue
  default: return .secondary
  }
}

struct ProtocolBadge: View {
  let parser: String

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: protocolIcon(for: parser)).imageScale(.small)
      Text(parser)
    }.font(.caption).fontWeight(.medium).padding(.horizontal, 8).padding(.vertical, 3).background(
      protocolColor(for: parser).opacity(0.15)
    ).foregroundStyle(protocolColor(for: parser)).clipShape(Capsule())
  }
}
