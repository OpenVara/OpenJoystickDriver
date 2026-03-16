import Foundation
import OpenJoystickDriverKit

private let appModelPollInterval = Duration.seconds(2)

/// Parsed, displayable representation of connected controller.
struct DeviceViewModel: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let vendorID: UInt16
  let productID: UInt16
  let parser: String
  /// "USB" or "HID"
  let connection: String
  /// USB serial number string, nil when unavailable.
  let serialNumber: String?

  /// Parse daemon description string of form:
  /// "NAME (VID:X PID:X PARSER [CONNECTION] SN:SERIAL)"
  static func parse(description: String) -> Self? {
    guard
      let parenRange = description.range(
        of: #"\(VID:(\d+) PID:(\d+) (\w+)"#,
        options: .regularExpression
      )
    else {
      return Self(
        id: description,
        name: description,
        vendorID: 0,
        productID: 0,
        parser: "Unknown",
        connection: "USB",
        serialNumber: nil
      )
    }

    let vid = parseVendorID(from: description, parenRange: parenRange)
    let pid = parseProductID(from: description, parenRange: parenRange)
    let parser = parseParser(from: description, parenRange: parenRange)
    let name = parseName(from: description)
    let connection = parseConnection(from: description)
    let serialNumber = parseSerialNumber(from: description)

    return Self(
      id: description,
      name: name.isEmpty ? description : name,
      vendorID: vid,
      productID: pid,
      parser: parser,
      connection: connection,
      serialNumber: serialNumber
    )
  }

  // MARK: - Private Parsers

  private static func parseVendorID(from description: String, parenRange: Range<String.Index>)
    -> UInt16
  {
    let parenStr = String(description[parenRange])
    let parts = parenStr.replacingOccurrences(of: "(", with: "").components(separatedBy: " ")
    return parts.first { $0.hasPrefix("VID:") }.flatMap { UInt16($0.dropFirst(4)) } ?? 0
  }

  private static func parseProductID(from description: String, parenRange: Range<String.Index>)
    -> UInt16
  {
    let parenStr = String(description[parenRange])
    let parts = parenStr.replacingOccurrences(of: "(", with: "").components(separatedBy: " ")
    return parts.first { $0.hasPrefix("PID:") }.flatMap { UInt16($0.dropFirst(4)) } ?? 0
  }

  private static func parseParser(from description: String, parenRange: Range<String.Index>)
    -> String
  {
    let parenStr = String(description[parenRange])
    let parts = parenStr.replacingOccurrences(of: "(", with: "").components(separatedBy: " ")
    return parts.first { !$0.hasPrefix("VID:") && !$0.hasPrefix("PID:") } ?? "Unknown"
  }

  private static func parseName(from description: String) -> String {
    guard let idx = description.firstIndex(of: "(") else { return description }
    return String(description[..<idx]).trimmingCharacters(in: .whitespaces)
  }

  private static func parseConnection(from description: String) -> String {
    guard let open = description.firstIndex(of: "["), let close = description.firstIndex(of: "]"),
      open < close
    else { return "USB" }
    return String(description[description.index(after: open)..<close])
  }

  private static func parseSerialNumber(from description: String) -> String? {
    guard let snRange = description.range(of: "SN:") else { return nil }
    let rest = description[snRange.upperBound...]
    let sn = String(rest.prefix { !$0.isWhitespace && $0 != ")" })
    return (sn.isEmpty || sn == "none") ? nil : sn
  }

}

/// Central observable model for GUI.
/// Polls daemon via XPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  @Published var daemonConnected = false
  @Published var daemonInstalled = false
  @Published var daemonRestarting = false
  @Published var daemonError: String?
  @Published var devices: [DeviceViewModel] = []
  @Published var inputMonitoring = "unknown"
  @Published var profiles: [Profile] = []
  @Published var extensionManager = SystemExtensionManager()
  var developerMode: Bool

  private let client = XPCClient()
  private var pollTask: Task<Void, Never>?

  init(developerMode: Bool = false) { self.developerMode = developerMode }

  func start() async {
    client.connect()
    refreshDaemonStatus()
    await poll()
    startPolling()
  }

  func refreshDaemonStatus() { daemonInstalled = DaemonManager.isInstalled }

  /// Path to daemon binary as recorded in installed LaunchAgent plist.
  /// Falls back to expected path relative to this app's executable.
  var daemonExecutablePath: String? {
    if let installed = DaemonManager.installedDaemonPath { return installed }
    guard let macosDir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
    // Prefer daemon inside its own bundle (required for provisioning profile on macOS 26+)
    let bundled = macosDir
      .appendingPathComponent("OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon")
    if FileManager.default.fileExists(atPath: bundled.path(percentEncoded: false)) {
      return bundled.path(percentEncoded: false)
    }
    return macosDir.appendingPathComponent("OpenJoystickDriverDaemon").path(percentEncoded: false)
  }

  func installDaemon() async {
    daemonError = nil
    guard let execURL = Bundle.main.executableURL else {
      daemonError = "Cannot locate app executable."
      return
    }
    let macosDir = execURL.deletingLastPathComponent()
    let bundledDaemon = macosDir
      .appendingPathComponent("OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon")
    let legacyDaemon = macosDir.appendingPathComponent("OpenJoystickDriverDaemon")
    let daemonURL = FileManager.default.fileExists(atPath: bundledDaemon.path(percentEncoded: false))
      ? bundledDaemon : legacyDaemon
    do {
      let task = Task.detached { try DaemonManager.install(daemonExecutable: daemonURL) }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    refreshDaemonStatus()
  }

  func startDaemon() async {
    daemonError = nil
    let task = Task.detached { DaemonManager.start() }
    await task.value
    try? await Task.sleep(for: .seconds(1))
    await poll()
  }

  func restartDaemon() async {
    daemonError = nil
    daemonRestarting = true
    let task = Task.detached { DaemonManager.restart() }
    await task.value
    client.disconnect()
    for _ in 0..<3 {
      try? await Task.sleep(for: .seconds(2))
      await poll()
      if daemonConnected { break }
    }
    if !daemonConnected {
      daemonError = "Daemon failed to restart. Try reinstalling."
    }
    daemonRestarting = false
  }

  func uninstallDaemon() async {
    daemonError = nil
    do {
      let task = Task.detached { try DaemonManager.uninstall() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    refreshDaemonStatus()
  }

  func saveProfile(_ profile: Profile) async throws {
    try await client.saveProfile(profile)
    await refreshProfiles()
  }

  func resetProfile(vendorID: UInt16, productID: UInt16) async throws {
    try await client.resetProfile(vendorID: vendorID, productID: productID)
    await refreshProfiles()
  }

  func refreshProfiles() async {
    do { profiles = try await client.listProfiles() } catch {
      print("[AppModel] refreshProfiles error: \(error)")
    }
  }

  func allProfiles(vendorID: UInt16, productID: UInt16) async throws -> [Profile] {
    try await client.allProfiles(vendorID: vendorID, productID: productID)
  }

  func addProfile(name: String, basedOn profile: Profile) async throws -> Profile {
    var copy = profile
    copy.id = UUID()
    copy.name = name
    return try await client.addProfile(copy)
  }

  func deleteProfile(id: UUID, vendorID: UInt16, productID: UInt16) async throws {
    try await client.deleteProfile(id: id, vendorID: vendorID, productID: productID)
  }

  func setActiveProfile(id: UUID, vendorID: UInt16, productID: UInt16) async throws {
    try await client.setActiveProfile(id: id, vendorID: vendorID, productID: productID)
  }

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }

  func setSuppressOutput(_ suppress: Bool) async { try? await client.setSuppressOutput(suppress) }

  private func poll() async {
    refreshDaemonStatus()
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      daemonConnected = true
      inputMonitoring = status.inputMonitoring
      devices = status.connectedDevices.compactMap(DeviceViewModel.parse(description:))
    } catch {
      daemonConnected = false
      devices = []
      // Daemon unreachable - fall back to checking this process's own permissions
      // so UI shows something useful rather than stale "unknown".
      let pm = PermissionManager()
      inputMonitoring = "\(await pm.checkAccess())"
    }

    await refreshProfiles()
  }

  private func startPolling() {
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: appModelPollInterval)
        await self?.poll()
      }
    }
  }
}
