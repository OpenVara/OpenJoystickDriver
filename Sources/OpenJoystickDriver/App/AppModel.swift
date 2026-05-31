import AppKit
import Foundation
import OpenJoystickDriverKit

private let appModelPollNanoseconds: UInt64 = 2_000_000_000
private let daemonHealthPollNanosecondsConnected: UInt64 = 15_000_000_000
private let daemonHealthPollNanosecondsDisconnected: UInt64 = 2_000_000_000

/// Parsed, displayable representation of connected controller.
struct DeviceViewModel: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let vendorID: UInt16
  let productID: UInt16
  let parser: String
  /// "USB" or "HID".
  let connection: String
  /// USB serial number string, nil when unavailable.
  let serialNumber: String?
  let supportsPhysicalRumble: Bool

  init(from description: XPCDeviceDescription) {
    self.id = "\(description.vendorID):\(description.productID):\(description.name)"
    self.name = description.name
    self.vendorID = description.vendorID
    self.productID = description.productID
    self.parser = description.parser
    self.connection = description.connection
    self.serialNumber = description.serialNumber
    self.supportsPhysicalRumble = description.supportsPhysicalRumble
  }
}

/// Central observable model for GUI.
///
/// Polls daemon via XPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  enum DaemonUIState: Equatable, Sendable {
    case missing
    case stopped
    case runningConnected
    case runningDisconnected
    case restarting
    case crashLooping
    case unknown
  }

  @Published var daemonConnected = false
  @Published var daemonInstalled = false
  @Published var daemonRestarting = false
  @Published var daemonError: String?
  @Published var daemonHealth: DaemonManager.DaemonHealth?
  @Published var devices: [DeviceViewModel] = []
  @Published var appInputMonitoring = "unknown"
  @Published var inputMonitoring = "unknown"
  @Published var inputMonitoringAssist: String?
  @Published var extensionManager = SystemExtensionManager()

  @Published var userSpaceVirtualDeviceEnabled = false
  @Published var userSpaceVirtualDeviceStatus = "unknown"
  @Published var virtualDeviceMode: String = VirtualDeviceMode.compatUserSpace.rawValue
  @Published var outputMode: String = CompositeOutputDispatcher.Mode.primaryOnly.rawValue
  @Published var compatibilityIdentity: String = CompatibilityIdentity.sdl2_3.rawValue
  @Published var virtualDeviceDiagnostics: XPCVirtualDeviceDiagnosticsPayload?
  @Published var virtualDeviceSelfTest: XPCVirtualDeviceSelfTestPayload?
  @Published var updateCheckState: UpdateCheckState = .idle

  var developerMode: Bool

  var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
  }

  private let client = XPCClient()
  private let permissionManager = PermissionManager()
  private let updateChecker = UpdateChecker()
  private var pollTask: Task<Void, Never>?

  private var lastHealthPollNs: UInt64 = 0

  // Tracks recent launchd restarts (based on `launchctl print runs = ...`) so the UI can
  // distinguish "stopped" from "restarting" and "crash-looping".
  private var lastDaemonRuns: Int?
  private var lastDaemonPid: Int?
  private var daemonStartEventsNs: [UInt64] = []

  init(developerMode: Bool = false) { self.developerMode = developerMode }

  var daemonUIState: DaemonUIState {
    if daemonRestarting { return .restarting }
    guard daemonInstalled else { return .missing }
    guard let h = daemonHealth, h.installed else {
      return daemonConnected ? .runningConnected : .unknown
    }

    if h.isInefficientKillLoop { return .crashLooping }
    if recentDaemonStartCount(windowSeconds: 10) >= 3 { return .crashLooping }
    if recentDaemonStartCount(windowSeconds: 4) > 0 && !daemonConnected { return .restarting }

    if daemonConnected { return .runningConnected }
    if h.pid != nil { return .runningDisconnected }
    if (h.state ?? "").uppercased() == "NOT_LOADED" { return .stopped }
    return .unknown
  }

  var daemonStatusLabel: String {
    switch daemonUIState {
    case .missing: return "missing"
    case .stopped: return "stopped"
    case .runningConnected: return "running"
    case .runningDisconnected: return "running (disconnected)"
    case .restarting: return "restarting…"
    case .crashLooping: return "crash-looping"
    case .unknown: return daemonConnected ? "running" : "unknown"
    }
  }

  var daemonSuggestedActionLabel: String? {
    switch daemonUIState {
    case .missing: return "Install Helper"
    case .stopped: return "Start Helper"
    case .runningDisconnected, .restarting, .crashLooping: return "Restart Helper"
    case .runningConnected, .unknown: return nil
    }
  }

  func start() async {
    refreshDaemonStatus()
    await refreshDaemonHealth()
    if daemonInstalled { client.connect() }
    await poll()
    await refreshVirtualDeviceDiagnostics()
    extensionManager.refreshInstallState()
    Task { await checkForUpdates() }
  }

  func setPollingEnabled(_ enabled: Bool) {
    if enabled {
      guard pollTask == nil else { return }
      startPolling()
      return
    }

    pollTask?.cancel()
    pollTask = nil
    client.disconnect()
  }

  func refreshDaemonStatus() { daemonInstalled = DaemonManager.isInstalled }

  func refreshDaemonHealth() async {
    let snapshot = await Task.detached { DaemonManager.health() }.value
    daemonHealth = snapshot
    noteDaemonHealth(snapshot)
    lastHealthPollNs = DispatchTime.now().uptimeNanoseconds
  }

  /// One-shot refresh used after lifecycle actions (install/start/restart/uninstall).
  ///
  /// This avoids relying on the 2s poll interval to correct UI state.
  func syncFromDaemonNow() async {
    refreshDaemonStatus()
    await refreshDaemonHealth()
    await poll()
    await refreshVirtualDeviceDiagnostics()
  }

  // MARK: - Daemon lifecycle

  func installDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Install") else { return }
    do {
      let task = Task.detached { try DaemonManager.install() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func startDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Start") else { return }
    do {
      let task = Task.detached { try DaemonManager.start() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func restartDaemon() async {
    daemonError = nil
    daemonRestarting = true
    guard ensureRunningFromApplications() else {
      daemonRestarting = false
      return
    }
    guard ensureBundleSignatureValid(for: "Restart") else {
      daemonRestarting = false
      return
    }
    do {
      let task = Task.detached { try DaemonManager.restart() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      daemonRestarting = false
      return
    }
    client.disconnect()
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    client.connect()
    await syncFromDaemonNow()
    daemonRestarting = false
  }

  func uninstallDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Uninstall") else { return }
    do {
      let task = Task.detached { try DaemonManager.uninstall() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    client.disconnect()
    await syncFromDaemonNow()
  }

  // MARK: - XPC-backed operations

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    guard daemonConnected else { return nil }
    return try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    guard daemonConnected else { return [] }
    return (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }

  func sendPhysicalRumble(
    vendorID: UInt16,
    productID: UInt16,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async -> Bool {
    guard daemonConnected else { return false }
    do {
      return try await client.sendPhysicalRumble(
        vendorID: vendorID,
        productID: productID,
        left: left,
        right: right,
        lt: lt,
        rt: rt,
        durationMs: durationMs
      )
    } catch {
      daemonError = formatDaemonError(error)
      return false
    }
  }

  func setSuppressOutput(_ suppress: Bool) async {
    guard daemonConnected else { return }
    try? await client.setSuppressOutput(suppress)
  }

  func setVirtualDeviceMode(_ modeRaw: String) async {
    guard daemonConnected else { return }
    do {
      try await client.setVirtualDeviceMode(modeRaw)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func setCompatibilityIdentity(_ raw: String) async {
    guard daemonConnected else { return }
    do {
      try await client.setCompatibilityIdentity(raw)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool) async {
    guard daemonConnected else { return }
    do {
      try await client.setUserSpaceVirtualDeviceEnabled(enabled)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func runVirtualDeviceSelfTest(seconds: Int = 5) async {
    guard daemonConnected else { return }
    do {
      virtualDeviceSelfTest = try await client.runVirtualDeviceSelfTest(seconds: seconds)
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
      virtualDeviceSelfTest = nil
    }
  }

  func refreshVirtualDeviceDiagnostics() async {
    guard daemonConnected else {
      virtualDeviceDiagnostics = nil
      return
    }
    do {
      virtualDeviceDiagnostics = try await client.getVirtualDeviceDiagnostics()
    } catch {
      daemonError = formatDaemonError(error)
      virtualDeviceDiagnostics = nil
    }
  }

  func checkForUpdates() async {
    updateCheckState = .checking
    updateCheckState = await updateChecker.check(currentVersion: appVersion)
  }

  func openLatestRelease() {
    if case .available(let info) = updateCheckState {
      NSWorkspace.shared.open(info.htmlURL)
    }
  }

  func requestAppInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    appInputMonitoring = "\(await permissionManager.requestAccess())"
    try? await Task.sleep(nanoseconds: 500_000_000)
    appInputMonitoring = "\(await permissionManager.checkAccess())"
    if appInputMonitoring != "granted" {
      openInputMonitoringSettings(for: ["OpenJoystickDriver"])
    }
  }

  func requestDaemonInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    guard daemonConnected else {
      inputMonitoringAssist =
        "Start OpenJoystickDriver Helper first so it can ask macOS for access."
      return
    }
    do {
      inputMonitoring = try await client.requestInputMonitoringAccess()
      try? await Task.sleep(nanoseconds: 500_000_000)
      await syncFromDaemonNow()
      if inputMonitoring != "granted" {
        openInputMonitoringSettings(for: ["OpenJoystickDriver Helper"])
      }
    } catch {
      daemonError = formatDaemonError(error)
    }
  }

  func openInputMonitoringSettings(
    for appNames: [String] = ["OpenJoystickDriver", "OpenJoystickDriver Helper"]
  ) {
    let names = appNames.joined(separator: " and ")
    inputMonitoringAssist =
      "OpenJoystickDriver asked macOS for access. In Input Monitoring, turn on \(names). " +
      "If macOS asks to quit and reopen, allow it."
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  // MARK: - Private

  private func formatDaemonError(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == 4099 {
      if let h = daemonHealth, h.isInefficientKillLoop {
        let runs = h.runs.map { "\($0)" } ?? "unknown"
        let active = h.activeCount.map { "\($0)" } ?? "unknown"
        return
          "Daemon was killed by launchd " +
          "(reason: inefficient, active=\(active), runs=\(runs)). " +
          "Restart or reinstall the daemon."
      }
      return "Lost connection to daemon (helper application). Restart the daemon."
    }
    if ns.domain == "NSXPCErrorDomain" {
      return "Lost connection to daemon. Restart the daemon."
    }
    return ns.localizedDescription
  }

  private func poll() async {
    refreshDaemonStatus()
    guard daemonInstalled else {
      daemonConnected = false
      devices = []
      userSpaceVirtualDeviceEnabled = false
      userSpaceVirtualDeviceStatus = "off"
      virtualDeviceDiagnostics = nil
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"
      resetDaemonHealthTrend()
      return
    }

    appInputMonitoring = "\(await permissionManager.checkAccess())"
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      daemonConnected = true
      daemonError = nil
      inputMonitoring = status.inputMonitoring
      devices = status.connectedDevices.map { DeviceViewModel(from: $0) }
      userSpaceVirtualDeviceEnabled = status.userSpaceVirtualDeviceEnabled ?? false
      userSpaceVirtualDeviceStatus = status.userSpaceVirtualDeviceStatus ?? "unknown"
      virtualDeviceMode = status.virtualDeviceMode ?? VirtualDeviceMode.compatUserSpace.rawValue
      outputMode = status.effectiveOutputMode ?? CompositeOutputDispatcher.Mode.primaryOnly.rawValue
      compatibilityIdentity = status.compatibilityIdentity ?? CompatibilityIdentity.sdl2_3.rawValue

      await maybeRefreshDaemonHealth(isConnected: true)
    } catch {
      daemonConnected = false
      devices = []
      client.disconnect()
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"

      // When XPC is failing, refresh launchd health immediately so we can explain why.
      await refreshDaemonHealth()

      // If launchd says the job is loaded/running but XPC isn't responding, call that out.
      if let h = daemonHealth, h.pid != nil {
        daemonError =
          "Couldn't communicate with the helper application. " +
          "The daemon is running but the connection was lost. Restart the daemon."
      } else {
        daemonError = formatDaemonError(error)
      }
    }
  }

  private func maybeRefreshDaemonHealth(isConnected: Bool) async {
    let now = DispatchTime.now().uptimeNanoseconds
    let intervalNs = isConnected ? daemonHealthPollNanosecondsConnected
      : daemonHealthPollNanosecondsDisconnected
    if daemonHealth == nil || now &- lastHealthPollNs >= intervalNs {
      await refreshDaemonHealth()
    }
  }

  private func noteDaemonHealth(_ snapshot: DaemonManager.DaemonHealth) {
    let now = DispatchTime.now().uptimeNanoseconds
    if !snapshot.installed || (snapshot.state ?? "").uppercased() == "NOT_LOADED" {
      resetDaemonHealthTrend()
      lastDaemonRuns = snapshot.runs
      lastDaemonPid = snapshot.pid
      return
    }

    if let runs = snapshot.runs {
      if let last = lastDaemonRuns, runs > last {
        for _ in 0..<(runs - last) { daemonStartEventsNs.append(now) }
      }
      lastDaemonRuns = runs
    }

    if let pid = snapshot.pid {
      if let lastPid = lastDaemonPid, pid != lastPid {
        daemonStartEventsNs.append(now)
      }
      lastDaemonPid = pid
    }

    let windowNs: UInt64 = 15 * 1_000_000_000
    daemonStartEventsNs.removeAll { now &- $0 > windowNs }
  }

  private func recentDaemonStartCount(windowSeconds: UInt64) -> Int {
    let now = DispatchTime.now().uptimeNanoseconds
    let windowNs = windowSeconds * 1_000_000_000
    return daemonStartEventsNs.filter { now &- $0 <= windowNs }.count
  }

  private func resetDaemonHealthTrend() {
    daemonStartEventsNs.removeAll(keepingCapacity: true)
    lastDaemonRuns = nil
    lastDaemonPid = nil
  }

  private func ensureRunningFromApplications() -> Bool {
    let path = Bundle.main.bundlePath
    if path.hasPrefix("/Applications/") { return true }
    daemonError =
      "Daemon install/restart requires running the app from /Applications. " +
      "Current app bundle: \(path)"
    return false
  }

  private func ensureBundleSignatureValid(for action: String) -> Bool {
    // SMAppService refuses to register an agent if the app bundle has been modified
    // after signing (e.g. copying the .dext into Contents/Library/SystemExtensions).
    //
    // When that happens, codesign reports:
    //   "a sealed resource is missing or invalid" + "file added: ..."
    let appPath = Bundle.main.bundlePath
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--verify", "--deep", "--strict", "--verbose=2", appPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      daemonError =
        "\(action) failed: could not run codesign verification " +
        "(\(error.localizedDescription))."
      return false
    }
    process.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus == 0 { return true }

    // Keep the UI message self-describing and fix-oriented.
    if out.contains("a sealed resource is missing or invalid") {
      daemonError =
        """
        \(action) failed: this app bundle's signature is INVALID.
        macOS thinks it was modified after signing.

        Typical cause: the system extension (.dext) was copied into the app without re-signing.

        Fix (no reboot):
          1) Run: ./scripts/ojd rebuild-fast dev
          2) Then re-try \(action)

        Diagnostic command:
          /usr/bin/codesign --verify --deep --strict --verbose=2 \(appPath)
        """
      return false
    }

    daemonError =
      """
      \(action) failed: app signature verification failed.

      Diagnostic output:
      \(out.trimmingCharacters(in: .whitespacesAndNewlines))
      """
    return false
  }

  private func startPolling() {
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: appModelPollNanoseconds)
        await self?.poll()
      }
    }
  }
}
