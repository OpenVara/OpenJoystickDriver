import Foundation
import SystemExtensions

private let ojdSystemExtensionID = "com.openjoystickdriver.VirtualHIDDevice"

struct SystemExtensionCommand {
  func run(arguments: [String]) {
    let subcommand = arguments.first ?? "status"
    switch subcommand {
    case "status": printStatus()
    case "install": submitActivation()
    case "uninstall": submitDeactivation()
    case "--help", "-h", "help": printHelp()
    default:
      print("Unknown sysext command: \(subcommand)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless sysext <command>

      Commands:
        status     Show registered OpenJoystickDriver system extensions
        install    Submit DriverKit system extension activation request
        uninstall  Submit DriverKit system extension deactivation request
      """
    )
  }

  private func printStatus() {
    let output = systemExtensionsList()
    let matches = output.split(separator: "\n").filter { $0.contains(ojdSystemExtensionID) }
    if matches.isEmpty {
      print("No OpenJoystickDriver system extension is registered.")
    } else {
      for line in matches { print(line) }
    }
  }

  private func submitActivation() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Install system extension")
    guard bundleContainsSystemExtension() else {
      print("ERROR: App bundle does not contain \(ojdSystemExtensionID).dext")
      print("Fix: run ./scripts/ojd rebuild dev, then retry from /Applications.")
      exit(1)
    }
    submit(.activation)
  }

  private func submitDeactivation() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Uninstall system extension")
    submit(.deactivation)
  }

  private func submit(_ mode: SystemExtensionSubmission.Mode) {
    let submission = SystemExtensionSubmission(mode: mode)
    submission.start()
    let result = submission.wait(timeout: 60)
    switch result {
    case .completed(let message):
      print(message)
    case .requiresApproval:
      print("System extension request submitted and requires approval in System Settings.")
      print("Open System Settings > General > Login Items & Extensions > Driver Extensions.")
    case .timedOut:
      print("System extension request did not finish within 60s.")
      print("Check System Settings for an approval prompt, then run sysext status.")
      exit(2)
    case .failed(let error):
      print(error)
      exit(1)
    }
  }

  private func bundleContainsSystemExtension() -> Bool {
    let bundlePath = Bundle.main.bundlePath
    let dextPath =
      bundlePath + "/Contents/Library/SystemExtensions/\(ojdSystemExtensionID).dext"
    return FileManager.default.fileExists(atPath: dextPath)
  }

  private func systemExtensionsList() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
    process.arguments = ["list"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return "systemextensionsctl failed: \(error.localizedDescription)"
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }
}

private final class SystemExtensionSubmission: NSObject, OSSystemExtensionRequestDelegate {
  enum Mode {
    case activation
    case deactivation
  }

  enum Result {
    case completed(String)
    case requiresApproval
    case timedOut
    case failed(String)
  }

  private let mode: Mode
  private var result: Result?

  init(mode: Mode) { self.mode = mode }

  func start() {
    let request: OSSystemExtensionRequest
    switch mode {
    case .activation:
      request = OSSystemExtensionRequest.activationRequest(
        forExtensionWithIdentifier: ojdSystemExtensionID,
        queue: .main
      )
    case .deactivation:
      request = OSSystemExtensionRequest.deactivationRequest(
        forExtensionWithIdentifier: ojdSystemExtensionID,
        queue: .main
      )
    }
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  func wait(timeout seconds: TimeInterval) -> Result {
    let deadline = Date().addingTimeInterval(seconds)
    while result == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    return result ?? .timedOut
  }

  func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    self.result = .completed(
      "System extension request finished with result \(result.rawValue)."
    )
  }

  func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    let nsError = error as NSError
    result = .failed(
      "System extension request failed: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
    )
  }

  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    result = .requiresApproval
  }

  func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    print(
      "Replacing \(existing.bundleIdentifier) v\(existing.bundleVersion) with v\(ext.bundleVersion)."
    )
    return .replace
  }
}
