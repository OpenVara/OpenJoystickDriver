import AppKit
import Foundation
import OpenJoystickDriverKit

private var appDelegate: AppDelegate?

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--headless") {
  let filtered = args.filter { $0 != "--headless" }
  CLI().run(arguments: filtered[...])
} else {
  let developerMode = args.contains("--developer-mode")
  appDelegate = AppDelegate(developerMode: developerMode)
  NSApplication.shared.delegate = appDelegate
  NSApplication.shared.run()
}
