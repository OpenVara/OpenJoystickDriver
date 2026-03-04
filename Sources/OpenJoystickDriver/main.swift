import AppKit
import Foundation
import OpenJoystickDriverKit

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--headless") {
  let filtered = args.filter { $0 != "--headless" }
  CLI().run(arguments: filtered[...])
} else {
  let delegate = AppDelegate()
  NSApplication.shared.delegate = delegate
  NSApplication.shared.run()
}
