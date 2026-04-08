import Foundation

/// Manages daemon LaunchAgent lifecycle.
///
/// Provides install and uninstall operations via launchctl operating on `~/Library/LaunchAgents`.
public enum DaemonManager: Sendable {
  /// Mach service label - also used as plist filename stem.
  public static let label = "com.openjoystickdriver.daemon"

  /// URL of user's LaunchAgent plist on disk.
  public static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/LaunchAgents/\(label).plist"
    )
  }

  /// Whether LaunchAgent plist is present on disk.
  public static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false))
  }

  /// Writes LaunchAgent plist and bootstraps daemon into the current user GUI session.
  ///
  /// - Parameter daemonExecutable: Full path to daemon binary.
  /// - Throws: A file system error if writing the plist or creating the directory fails.
  public static func install(daemonExecutable: URL) throws {
    let plist = makePlist(daemonPath: daemonExecutable.path(percentEncoded: false))
    let agentsDir = plistURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: agentsDir.path(percentEncoded: false)) {
      try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
    }
    try plist.write(to: plistURL, atomically: true, encoding: .utf8)
    let uid = String(getuid())
    // If an older job is already loaded, boot it out first to keep install idempotent.
    _ = try? launchctl(["bootout", "gui/\(uid)/\(label)"])
    try launchctl(["bootstrap", "gui/\(uid)", plistURL.path(percentEncoded: false)])
    _ = try? launchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
    print("[DaemonManager] Installed")
  }

  /// Starts daemon via launchctl kickstart.
  ///
  /// Use when LaunchAgent is installed but not running.
  public static func start() throws {
    let uid = String(getuid())
    try launchctl(["kickstart", "gui/\(uid)/\(label)"])
    print("[DaemonManager] Started")
  }

  /// Kills and restarts daemon via launchctl kickstart -k.
  ///
  /// Use to apply permission grants without full reinstall.
  public static func restart() throws {
    let uid = String(getuid())
    try launchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
    print("[DaemonManager] Restarted")
  }

  /// Returns daemon executable path from installed LaunchAgent plist.
  ///
  /// Returns nil if plist is absent or unparseable.
  public static var installedDaemonPath: String? {
    guard let data = try? Data(contentsOf: plistURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any], let args = plist["ProgramArguments"] as? [String]
    else { return nil }
    return args.first
  }

  /// Unloads daemon and removes LaunchAgent plist.
  public static func uninstall() throws {
    let uid = String(getuid())
    _ = try? launchctl(["bootout", "gui/\(uid)/\(label)"])
    if FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: plistURL)
    }
    print("[DaemonManager] Uninstalled")
  }

  // MARK: - Diagnostics

  public struct DaemonHealth: Sendable, Equatable {
    public var installed: Bool
    public var state: String?
    public var pid: Int?
    public var runs: Int?
    public var immediateReason: String?
    public var lastTerminatingSignal: String?
    public var blame: String?
    public var rawPrint: String?

    public init(
      installed: Bool,
      state: String? = nil,
      pid: Int? = nil,
      runs: Int? = nil,
      immediateReason: String? = nil,
      lastTerminatingSignal: String? = nil,
      blame: String? = nil,
      rawPrint: String? = nil
    ) {
      self.installed = installed
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

  /// Best-effort snapshot of launchd state for the daemon job.
  ///
  /// This is used to explain "couldn't communicate with a helper application"
  /// XPC errors, which commonly occur when launchd kills/restarts the job.
  public static func health() -> DaemonHealth {
    guard isInstalled else { return DaemonHealth(installed: false) }
    let uid = String(getuid())
    let target = "gui/\(uid)/\(label)"

    let printOut = (try? launchctl(["print", target])) ?? ""
    let blameOut = (try? launchctl(["blame", target]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    var health = DaemonHealth(installed: true, blame: blameOut, rawPrint: printOut)

    for rawLine in printOut.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("state = ") {
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

  // MARK: - Private

  @discardableResult private static func launchctl(_ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }

  private static func makePlist(daemonPath: String) -> String {
    // MachServices must be declared so launchd allows NSXPCListener to register
    // service. Without this entry, launchd kills process with SIGKILL
    // exactly when NSXPCListener.resume() is called.
    let escapedLabel = xmlEscape(label)
    let escapedPath = xmlEscape(daemonPath)
    let escapedService = xmlEscape(xpcServiceName)
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>\(escapedLabel)</string>
        <key>ProgramArguments</key>
        <array>
          <string>\(escapedPath)</string>
        </array>
        <key>MachServices</key>
        <dict>
          <key>\(escapedService)</key>
          <true/>
        </dict>
        <key>KeepAlive</key>
        <true/>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>/tmp/\(escapedLabel).err</string>
        <key>StandardOutPath</key>
        <string>/tmp/\(escapedLabel).out</string>
      </dict>
      </plist>
      """
  }

  private static func xmlEscape(_ string: String) -> String {
    string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
