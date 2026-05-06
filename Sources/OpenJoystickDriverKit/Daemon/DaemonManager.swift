import Foundation
import ServiceManagement

/// Manages daemon LaunchAgent lifecycle.
///
/// Uses ServiceManagement (`SMAppService`) on macOS 13 and newer, with a
/// launchd plist fallback for macOS 10.15 through 12.
public enum DaemonManager: Sendable {
  /// Launchd job label.
  public static let label = "com.openjoystickdriver.daemon"

  /// Name of the LaunchAgent plist embedded in OpenJoystickDriver.app.
  ///
  /// Must exist at:
  ///   `OpenJoystickDriver.app/Contents/Library/LaunchAgents/<plistName>`
  public static let agentPlistName = "\(label).plist"

  @available(macOS 13.0, *)
  private static var appService: SMAppService {
    SMAppService.agent(plistName: agentPlistName)
  }

  /// Whether the daemon LaunchAgent is registered for the current user.
  public static var isInstalled: Bool {
    if #available(macOS 13.0, *) {
      switch appService.status {
      case .notRegistered: return false
      default: return true
      }
    }
    return legacyIsInstalled
  }

  /// Registers the daemon LaunchAgent.
  ///
  /// - Important: The LaunchAgent plist must be embedded in the app bundle.
  public static func install() throws {
    do {
      if #available(macOS 13.0, *) {
        try appService.register()
        print("[DaemonManager] Installed (SMAppService)")
      } else {
        try legacyInstall()
        print("[DaemonManager] Installed (launchctl)")
      }
    } catch {
      throw wrap(error, hint: installHint())
    }
  }

  /// Unregisters the daemon LaunchAgent.
  public static func uninstall() throws {
    do {
      if #available(macOS 13.0, *) {
        try appService.unregister()
        print("[DaemonManager] Uninstalled (SMAppService)")
      } else {
        try legacyUninstall()
        print("[DaemonManager] Uninstalled (launchctl)")
      }
    } catch {
      throw wrap(error, hint: uninstallHint())
    }
  }

  /// Starts the daemon (idempotent).
  ///
  /// ServiceManagement does not have a separate "start" primitive; registering
  /// or bootstrapping an agent with `RunAtLoad` starts it.
  public static func start() throws { try install() }

  /// Restarts the daemon (best-effort).
  public static func restart() throws {
    do {
      if #available(macOS 13.0, *) {
        // Unregister+register is the most reliable cross-shell restart path.
        try? appService.unregister()
        try appService.register()
        print("[DaemonManager] Restarted (SMAppService)")
      } else {
        try legacyRestart()
        print("[DaemonManager] Restarted (launchctl)")
      }
    } catch {
      throw wrap(error, hint: restartHint())
    }
  }

  /// Best-effort snapshot of launchd state for the daemon job.
  ///
  /// This is used to explain "couldn't communicate with a helper application"
  /// XPC errors, which commonly occur when launchd kills/restarts the job.
  public static func health() -> DaemonHealth {
    guard isInstalled else { return DaemonHealth(installed: false) }
    let uid = String(getuid())
    let target = "gui/\(uid)/\(label)"

    var printOut = ""
    var printErr: String?
    do {
      printOut = try launchctl(["print", target])
    } catch {
      printErr = error.localizedDescription
    }

    let blameOut =
      (try? launchctl(["blame", target]))?.trimmingCharacters(in: .whitespacesAndNewlines)

    var health = DaemonHealth(
      installed: true,
      state: printErr == nil ? nil : "NOT_LOADED",
      blame: blameOut,
      rawPrint: (printErr == nil) ? printOut : "launchctl print failed:\n\(printErr!)"
    )

    if printErr != nil {
      return health
    }

    for rawLine in printOut.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("active count = ") {
        health.activeCount = Int(line.dropFirst("active count = ".count))
      } else if line.hasPrefix("state = ") {
        health.state = String(line.dropFirst("state = ".count))
      } else if line.hasPrefix("pid = ") {
        health.pid = Int(line.dropFirst("pid = ".count))
      } else if line.hasPrefix("runs = ") {
        health.runs = Int(line.dropFirst("runs = ".count))
      } else if line.hasPrefix("immediate reason = ") {
        health.immediateReason = String(line.dropFirst("immediate reason = ".count))
      } else if line.hasPrefix("last terminating signal = ") {
        health.lastTerminatingSignal = String(line.dropFirst("last terminating signal = ".count))
      }
    }

    return health
  }

  public struct DaemonHealth: Sendable {
    public var installed: Bool
    public var activeCount: Int?
    public var state: String?
    public var pid: Int?
    public var runs: Int?
    public var immediateReason: String?
    public var lastTerminatingSignal: String?
    public var blame: String?
    public var rawPrint: String?

    public init(
      installed: Bool,
      activeCount: Int? = nil,
      state: String? = nil,
      pid: Int? = nil,
      runs: Int? = nil,
      immediateReason: String? = nil,
      lastTerminatingSignal: String? = nil,
      blame: String? = nil,
      rawPrint: String? = nil
    ) {
      self.installed = installed
      self.activeCount = activeCount
      self.state = state
      self.pid = pid
      self.runs = runs
      self.immediateReason = immediateReason
      self.lastTerminatingSignal = lastTerminatingSignal
      self.blame = blame
      self.rawPrint = rawPrint
    }

    public var wasSigkill9: Bool {
      (lastTerminatingSignal ?? "").contains("Killed: 9")
    }

    public var isInefficientKillLoop: Bool {
      let reason = (immediateReason ?? blame ?? "").lowercased()
      return wasSigkill9 && reason.contains("inefficient")
    }
  }

  // MARK: - Private

  private static var launchdDomain: String { "gui/\(getuid())" }
  private static var launchdTarget: String { "\(launchdDomain)/\(label)" }

  private static var bundledLaunchAgentURL: URL {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
      .appendingPathComponent(agentPlistName)
  }

  private static var installedLaunchAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
      .appendingPathComponent(agentPlistName)
  }

  private static var legacyIsInstalled: Bool {
    if (try? launchctl(["print", launchdTarget])) != nil { return true }
    return FileManager.default.fileExists(atPath: installedLaunchAgentURL.path)
  }

  private static func legacyInstall() throws {
    try installLaunchAgentPlist()
    _ = try? launchctl(["bootout", launchdTarget])
    try launchctl(["bootstrap", launchdDomain, installedLaunchAgentURL.path])
  }

  private static func legacyUninstall() throws {
    _ = try? launchctl(["bootout", launchdTarget])
    if FileManager.default.fileExists(atPath: installedLaunchAgentURL.path) {
      try FileManager.default.removeItem(at: installedLaunchAgentURL)
    }
  }

  private static func legacyRestart() throws {
    try installLaunchAgentPlist()
    _ = try? launchctl(["bootout", launchdTarget])
    try launchctl(["bootstrap", launchdDomain, installedLaunchAgentURL.path])
    _ = try? launchctl(["kickstart", "-k", launchdTarget])
  }

  private static func installLaunchAgentPlist() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: bundledLaunchAgentURL.path) else {
      throw NSError(
        domain: "OpenJoystickDriver.DaemonManager",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "LaunchAgent plist not found at \(bundledLaunchAgentURL.path)."
        ]
      )
    }
    let directory = installedLaunchAgentURL.deletingLastPathComponent()
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    if fm.fileExists(atPath: installedLaunchAgentURL.path) {
      try fm.removeItem(at: installedLaunchAgentURL)
    }
    try fm.copyItem(at: bundledLaunchAgentURL, to: installedLaunchAgentURL)
  }

  private static func wrap(_ error: Error, hint: String) -> NSError {
    NSError(
      domain: "OpenJoystickDriver.DaemonManager",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription)\n\n\(hint)"]
    )
  }

  private static func installHint() -> String {
    """
    Fix checklist:
      1) Run the /Applications copy: `/Applications/OpenJoystickDriver.app` (not `.build/...`).
      2) Ensure the app bundle contains: `Contents/Library/LaunchAgents/\(agentPlistName)`.
      3) If a previous daemon is stuck, uninstall first: `OpenJoystickDriver --headless uninstall`.
    """
  }

  private static func uninstallHint() -> String {
    """
    Fix checklist:
      1) Make sure you're running the /Applications copy of the app.
      2) Check daemon log: `tail -n 80 /tmp/\(label).out` and `/tmp/\(label).err`.
    """
  }

  private static func restartHint() -> String {
    """
    Fix checklist:
      1) Try uninstall+install: `OpenJoystickDriver --headless uninstall` then `OpenJoystickDriver --headless install`.
      2) Check daemon log: `tail -n 80 /tmp/\(label).out` and `/tmp/\(label).err`.
      3) Check launchd health: `launchctl print gui/$(id -u)/\(label) | head -n 80`
    """
  }

  private struct LaunchctlError: LocalizedError, Sendable {
    let args: [String]
    let status: Int32
    let output: String

    var errorDescription: String? {
      let cmd = (["launchctl"] + args).joined(separator: " ")
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        return "\(cmd) failed (exit status \(status))."
      }
      return "\(cmd) failed (exit status \(status)):\n\(trimmed)"
    }
  }

  @discardableResult private static func launchctl(_ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
      throw LaunchctlError(args: args, status: process.terminationStatus, output: out)
    }
    return out
  }
}
