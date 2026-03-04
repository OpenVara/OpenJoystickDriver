import Foundation
import OpenJoystickDriverKit

struct CLI {
  func run(arguments: ArraySlice<String>) {
    let args = Array(arguments)
    let command = args.first ?? "run"

    switch command {
    case "list": ListCommand().run()
    case "status": StatusCommand().run()
    case "diagnose": DiagnoseCommand().run()
    case "profile": ProfileCommand(args: Array(args.dropFirst())).run()
    case "start": StartDaemonCommand().run()
    case "restart": RestartDaemonCommand().run()
    case "install": InstallCommand().run()
    case "uninstall": UninstallCommand().run()
    case "run": RunCommand().run()
    case "--help", "-h", "help": printHelp()
    case "--version", "-v", "version": print("OpenJoystickDriver v0.1.0")
    default:
      print("Unknown command: \(command)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      OpenJoystickDriver v0.1.0 \
      - macOS gamepad driver

      Usage: OpenJoystickDriver \
      --headless <command>

      Commands:
        run        Start driver \
      (default - processes controller input)
        list       List connected game controllers
        status     Show permission and device status
        diagnose   Hardware diagnostics
        profile    Manage controller profiles \
      (list|show|set|reset)
        install    Install daemon as LaunchAgent \
      (auto-starts on login)
        uninstall  Remove daemon LaunchAgent
        start      Start daemon LaunchAgent
        restart    Restart daemon LaunchAgent

      Options:
        -h, --help     Show this help
        -v, --version  Show version
      """
    )
  }
}
