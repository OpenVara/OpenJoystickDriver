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
    case "userspace": UserSpaceCommand().run(arguments: Array(args.dropFirst()))
    case "output": OutputModeCommand().run(arguments: Array(args.dropFirst()))
    case "compat": CompatibilityCommand().run(arguments: Array(args.dropFirst()))
    case "selftest": SelfTestCommand().run(arguments: Array(args.dropFirst()))
    case "start": StartDaemonCommand().run()
    case "restart": RestartDaemonCommand().run()
    case "reset-settings": ResetSettingsCommand().run()
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
        userspace  Toggle user-space virtual gamepad (IOHIDUserDevice)
        output     Set output routing mode (DriverKit/user-space)
        compat     Set compatibility identity (generic/xboxOne)
        selftest   Count input events on virtual devices
        install    Register daemon LaunchAgent (SMAppService)
        uninstall  Unregister daemon LaunchAgent
        start      Start daemon (register if needed)
        restart    Restart daemon (unregister+register)
        reset-settings Reset daemon settings (mode/identity/output)

      Options:
        -h, --help     Show this help
        -v, --version  Show version
      """
    )
  }
}
