import Foundation
import SystemExtensions

/// Manages installation and removal of the `com.openjoystickdriver.VirtualHIDDevice`
/// DriverKit system extension via `OSSystemExtensionManager`.
///
/// Usage: call ``installExtension()`` from the GUI; monitor ``installState`` for
/// progress. The extension must be embedded in the app bundle under
/// `Contents/Library/SystemExtensions/OpenJoystickVirtualHID.dext`.
///
/// The GUI app requires `com.apple.developer.system-extension.install` in its
/// entitlements (`Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements`).
///
/// - Note: `@unchecked Sendable` suppresses the Sendable warning that arises
///   when `AppModel` (a `@MainActor` class) holds a reference to this object.
///   All `@Published` mutations happen on the main queue (the delegate callbacks
///   use `queue: .main` and `Task { @MainActor in }`).
@MainActor final class SystemExtensionManager: NSObject, ObservableObject, @unchecked Sendable {

  // MARK: - Install state

  enum InstallState: Equatable {
    case unknown
    case installing
    case requiresApproval
    case installed
    case removing
    case failed(String)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case (.unknown, .unknown), (.installing, .installing), (.requiresApproval, .requiresApproval),
        (.installed, .installed), (.removing, .removing):
        return true
      case (.failed(let a), .failed(let b)): return a == b
      default: return false
      }
    }

    var label: String {
      switch self {
      case .unknown: return "Unknown"
      case .installing: return "Installing…"
      case .requiresApproval: return "Requires Approval"
      case .installed: return "Installed"
      case .removing: return "Removing…"
      case .failed(let msg): return "Failed: \(msg)"
      }
    }

    var isInstalled: Bool { self == .installed }
    var isPending: Bool { self == .installing || self == .requiresApproval }
  }

  @Published var installState: InstallState = .unknown
  /// Non-fatal warning shown when the extension appears installed but the last request failed.
  @Published var installWarning: String?
  /// Human-readable, safe diagnostics for why system extension install failed.
  ///
  /// Intended to be shown in the UI so users can fix issues without Console.
  @Published var lastInstallDetails: [String] = []
  private var pendingDeactivation = false

  // MARK: - Constants

  private let extensionBundleID = "com.openjoystickdriver.VirtualHIDDevice"
  private let expectedDextRelativePath =
    "Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext"

  // MARK: - Public API

  func installExtension() {
    installState = .installing
    installWarning = nil
    lastInstallDetails = []

    let preflight = preflightStatus()
    lastInstallDetails = preflight.details

    // If the system extension isn't inside *this* app bundle, activation will fail with
    // OSSystemExtensionErrorExtensionNotFound (code=4). Fail early with an actionable message.
    guard preflight.hasExpectedDext else {
      installState = .failed(
        """
        Extension not found in this app (code=4).
        Fix: reinstall/rebuild the app so it contains the .dext, then run the /Applications copy.
        """
      )
      return
    }

    let request = OSSystemExtensionRequest.activationRequest(
      forExtensionWithIdentifier: extensionBundleID,
      queue: .main
    )
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  func uninstallExtension() {
    installState = .removing
    installWarning = nil
    pendingDeactivation = true
    let request = OSSystemExtensionRequest.deactivationRequest(
      forExtensionWithIdentifier: extensionBundleID,
      queue: .main
    )
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  /// Best-effort refresh that uses `systemextensionsctl list` to see whether the extension
  /// is already active, and clears stale error banners when it is.
  func refreshInstallState() {
    let preflight = preflightStatus()
    lastInstallDetails = preflight.details
    guard preflight.hasExpectedDext else {
      installState = .unknown
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      let active = await Self.isSysextActiveAsync(extensionID: self.extensionBundleID)
      if active {
        self.installState = .installed
      } else if self.installState.isPending {
        // Keep pending state while OSSystemExtensionManager is working.
      } else {
        self.installState = .unknown
      }
    }
  }

}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {

  nonisolated func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    print("[SysExt] didFinishWithResult: \(result) (rawValue: \(result.rawValue))")
    Task { @MainActor [weak self] in
      guard let self else { return }
      if self.pendingDeactivation {
        self.pendingDeactivation = false
        self.installState = .unknown
      } else {
        self.installState = .installed
      }
    }
  }

  nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    let nsError = error as NSError
    print("[SysExt] FAILED — domain: \(nsError.domain), code: \(nsError.code)")
    print("[SysExt]   localizedDescription: \(nsError.localizedDescription)")

    let message: String = {
      if nsError.domain == OSSystemExtensionErrorDomain {
        // IMPORTANT: OSSystemExtensionErrorDomain codes are not stable across macOS versions
        // and code=4 is used for multiple failure modes in the field.
        //
        // Do not claim "not found" here; instead show safe, actionable next steps.
        let code = nsError.code
        var lines: [String] = []
        lines.append("System Extension install failed (OSSystemExtensionErrorDomain code=\(code)).")
        lines.append(nsError.localizedDescription)
        lines.append("")
        lines.append("Fix checklist (no guesswork):")
        lines.append("  1) Make sure you are running `/Applications/OpenJoystickDriver.app` (not `.build/...`).")
        lines.append("  2) If you are streaming / cannot reboot: use `./scripts/ojd rebuild-fast dev` to avoid sysext upgrades.")
        lines.append("  3) If you see \"stale sysext copies\" in diagnostics, macOS typically needs a reboot to fully clean up old versions.")
        lines.append("  4) Meanwhile, you can still use Compatibility mode (user-space virtual device) without touching the system extension.")
        return lines.joined(separator: "\n")
      }
      return "\(nsError.localizedDescription) [code=\(nsError.code)]"
    }()
    Task { @MainActor [weak self] in
      guard let self else { return }
      // Capture fresh preflight details for the UI.
      self.lastInstallDetails = self.preflightStatus().details
      self.pendingDeactivation = false
      self.installState = .failed(message)

      // If the extension is already active, treat this as a warning rather than a blocker.
      // This happens frequently during sysext replacement/upgrade when a reboot is needed
      // to clean up stale copies.
      if Self.isSysextActive(extensionID: self.extensionBundleID) {
        self.installWarning =
          "DriverKit extension appears active, but the last install request failed. If diagnostics mention stale copies, a reboot cleans them up."
        self.installState = .installed
      }
    }
  }

  nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    Task { @MainActor [weak self] in self?.installState = .requiresApproval }
  }

  nonisolated func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    print("[SysExt] actionForReplacingExtension called")
    print(
      "[SysExt]   existing: \(existing.bundleIdentifier)"
        + " v\(existing.bundleVersion) (\(existing.bundleShortVersion))"
    )
    print(
      "[SysExt]   new:      \(ext.bundleIdentifier)"
        + " v\(ext.bundleVersion) (\(ext.bundleShortVersion))"
    )
    return .replace
  }
}

// MARK: - Preflight

extension SystemExtensionManager {
  private struct Preflight: Sendable {
    var hasExpectedDext: Bool
    var details: [String]
  }

  /// Collects safe, human-readable diagnostics for system extension activation.
  private func preflightStatus() -> Preflight {
    let bundlePath = Bundle.main.bundlePath
    let sysextDir = bundlePath + "/Contents/Library/SystemExtensions"
    let expectedDextPath = bundlePath + "/" + expectedDextRelativePath

    var details: [String] = []
    details.append("App bundle: \(bundlePath)")
    details.append("Looking for extension id: \(extensionBundleID)")
    details.append("SystemExtensions folder: \(sysextDir)")
    details.append("Expected .dext path: \(expectedDextPath)")

    let fm = FileManager.default
    guard fm.fileExists(atPath: sysextDir) else {
      details.append("Result: missing SystemExtensions folder")
      return Preflight(hasExpectedDext: false, details: details)
    }

    guard let items = try? fm.contentsOfDirectory(atPath: sysextDir) else {
      details.append("Result: SystemExtensions folder unreadable")
      return Preflight(hasExpectedDext: false, details: details)
    }

    let dexts = items.filter { $0.hasSuffix(".dext") }
    if dexts.isEmpty {
      details.append("Result: no .dext bundles found")
      return Preflight(hasExpectedDext: false, details: details)
    }

    details.append("Found .dext bundles:")
    var hasExpected = false
    for item in dexts.sorted() {
      let dextPath = sysextDir + "/" + item
      let bundleID = Bundle(path: dextPath)?.bundleIdentifier ?? "UNKNOWN"
      details.append("  - \(item) (id: \(bundleID))")
      if bundleID == extensionBundleID { hasExpected = true }
    }

    details.append("Result: " + (hasExpected ? "expected extension present" : "expected extension missing"))
    return Preflight(hasExpectedDext: hasExpected, details: details)
  }

  nonisolated private static func isSysextActive(extensionID: String) -> Bool {
    guard !extensionID.isEmpty else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
    process.arguments = ["list"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return false
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8) ?? ""
    if !out.contains(extensionID) { return false }
    // Heuristic: the line usually contains "[activated enabled]" when active.
    return out.split(separator: "\n").contains { line in
      line.contains(extensionID) && line.localizedCaseInsensitiveContains("activated enabled")
    }
  }

  private static func isSysextActiveAsync(extensionID: String) async -> Bool {
    await withCheckedContinuation { cont in
      DispatchQueue.global(qos: .utility).async {
        cont.resume(returning: isSysextActive(extensionID: extensionID))
      }
    }
  }
}
