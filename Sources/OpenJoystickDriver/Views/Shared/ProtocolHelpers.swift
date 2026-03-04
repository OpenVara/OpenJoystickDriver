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
