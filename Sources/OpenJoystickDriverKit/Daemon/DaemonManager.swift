import Foundation

/// Manages daemon LaunchAgent lifecycle.
/// Provides install and uninstall operations via launchctl
/// operating on ~/Library/LaunchAgents.
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

  /// Writes LaunchAgent plist and bootstraps daemon
  /// into current user GUI session.
  ///
  /// - Parameter daemonExecutable: Full path to daemon binary.
  public static func install(daemonExecutable: URL) throws {
    let plist = makePlist(daemonPath: daemonExecutable.path(percentEncoded: false))
    let agentsDir = plistURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: agentsDir.path(percentEncoded: false)) {
      try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
    }
    try plist.write(to: plistURL, atomically: true, encoding: .utf8)
    let uid = String(getuid())
    launchctl(["bootstrap", "gui/\(uid)", plistURL.path(percentEncoded: false)])
    print("[DaemonManager] Installed")
  }

  /// Starts daemon via launchctl kickstart.
  /// Use when LaunchAgent is installed but not running.
  public static func start() {
    let uid = String(getuid())
    launchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
    print("[DaemonManager] Started")
  }

  /// Kills and restarts daemon via launchctl kickstart -k.
  /// Use to apply permission grants without full reinstall.
  public static func restart() {
    let uid = String(getuid())
    launchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
    print("[DaemonManager] Restarted")
  }

  /// Returns daemon executable path from installed LaunchAgent plist.
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
    launchctl(["bootout", "gui/\(uid)/\(label)"])
    if FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: plistURL)
    }
    print("[DaemonManager] Uninstalled")
  }

  // MARK: - Private

  @discardableResult private static func launchctl(_ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }

  private static func makePlist(daemonPath: String) -> String {
    // MachServices must be declared so launchd allows NSXPCListener to register
    // service. Without this entry, launchd kills process with SIGKILL
    // exactly when NSXPCListener.resume() is called.
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(label)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(daemonPath)</string>
      </array>
      <key>MachServices</key>
      <dict>
        <key>\(xpcServiceName)</key>
        <true/>
      </dict>
      <key>KeepAlive</key>
      <true/>
      <key>RunAtLoad</key>
      <true/>
      <key>StandardErrorPath</key>
      <string>/tmp/\(label).err</string>
      <key>StandardOutPath</key>
      <string>/tmp/\(label).out</string>
    </dict>
    </plist>
    """
  }
}
