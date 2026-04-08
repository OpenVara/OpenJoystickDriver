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
  /// "USB" or "HID".
  let connection: String
  /// USB serial number string, nil when unavailable.
  let serialNumber: String?

  init(from description: XPCDeviceDescription) {
    self.id = "\(description.vendorID):\(description.productID):\(description.name)"
    self.name = description.name
    self.vendorID = description.vendorID
    self.productID = description.productID
    self.parser = description.parser
    self.connection = description.connection
    self.serialNumber = description.serialNumber
  }

}

/// Central observable model for GUI.
///
/// Polls daemon via XPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  @Published var daemonConnected = false
  @Published var daemonInstalled = false
  @Published var daemonRestarting = false
  @Published var daemonError: String?
  @Published var daemonHealth: DaemonManager.DaemonHealth?
  @Published var devices: [DeviceViewModel] = []
  @Published var inputMonitoring = "unknown"
  @Published var extensionManager = SystemExtensionManager()
  @Published var userSpaceVirtualDeviceEnabled = false
  @Published var userSpaceVirtualDeviceStatus = "unknown"
  @Published var virtualDeviceMode: String = VirtualDeviceMode.auto.rawValue
  @Published var outputMode: String = "primaryOnly"
  @Published var virtualDeviceDiagnostics: XPCVirtualDeviceDiagnosticsPayload?
  @Published var virtualDeviceSelfTest: XPCVirtualDeviceSelfTestPayload?
  var developerMode: Bool

  private let client = XPCClient()
  private let permissionManager = PermissionManager()
  private var pollTask: Task<Void, Never>?

  init(developerMode: Bool = false) { self.developerMode = developerMode }

  func start() async {
    client.connect()
    refreshDaemonStatus()
    await refreshDaemonHealth()
    await poll()
    await refreshOutputMode()
    await refreshVirtualDeviceDiagnostics()
    startPolling()
  }

  func refreshDaemonStatus() { daemonInstalled = DaemonManager.isInstalled }

  func refreshDaemonHealth() async {
    let snapshot = await Task.detached { DaemonManager.health() }.value
    daemonHealth = snapshot
  }

  /// One-shot refresh used after lifecycle actions (install/start/restart/uninstall).
  ///
  /// This avoids relying on the 2s poll interval to correct UI state after
  /// daemon restarts or XPC disconnects.
  func syncFromDaemonNow() async {
    refreshDaemonStatus()
    await refreshDaemonHealth()
    if !client.isConnected { client.connect() }
    await poll()
    await refreshOutputMode()
    await refreshVirtualDeviceDiagnostics()
  }

  /// Path to daemon binary as recorded in installed LaunchAgent plist.
  ///
  /// Falls back to expected path relative to this app's executable.
  var daemonExecutablePath: String? {
    if let installed = DaemonManager.installedDaemonPath { return installed }
    guard let macosDir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
    // Prefer daemon inside its own bundle (required for provisioning profile on macOS 26+)
    let daemonSubpath = "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
    let bundled = macosDir.appendingPathComponent(daemonSubpath)
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
    let daemonSubpath = "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
    let bundledDaemon = macosDir.appendingPathComponent(daemonSubpath)
    let legacyDaemon = macosDir.appendingPathComponent("OpenJoystickDriverDaemon")
    let bundledPath = bundledDaemon.path(percentEncoded: false)
    let daemonURL =
      FileManager.default.fileExists(atPath: bundledPath) ? bundledDaemon : legacyDaemon
    do {
      let task = Task.detached { try DaemonManager.install(daemonExecutable: daemonURL) }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    refreshDaemonStatus()
    await refreshDaemonHealth()
  }

  func startDaemon() async {
    daemonError = nil
    do {
      let task = Task.detached { try DaemonManager.start() }
      try await task.value
    } catch {
      daemonError = formatDaemonError(error)
      return
    }
    try? await Task.sleep(for: .seconds(1))
    await poll()
    await refreshDaemonHealth()
  }

  func restartDaemon() async {
    daemonError = nil
    daemonRestarting = true
    do {
      let task = Task.detached { try DaemonManager.restart() }
      try await task.value
    } catch {
      daemonError = formatDaemonError(error)
      daemonRestarting = false
      return
    }
    client.disconnect()
    for _ in 0..<3 {
      try? await Task.sleep(for: .seconds(2))
      await poll()
      if daemonConnected { break }
    }
    if !daemonConnected { daemonError = "Daemon failed to restart. Try reinstalling." }
    await refreshDaemonHealth()
    daemonRestarting = false
  }

  func uninstallDaemon() async {
    daemonError = nil
    do {
      let task = Task.detached { try DaemonManager.uninstall() }
      try await task.value
    } catch {
      daemonError = formatDaemonError(error)
      return
    }
    refreshDaemonStatus()
    await refreshDaemonHealth()
  }

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }

  func setSuppressOutput(_ suppress: Bool) async { try? await client.setSuppressOutput(suppress) }

  func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool) async {
    do {
      try await client.setUserSpaceVirtualDeviceEnabled(enabled)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func setVirtualDeviceMode(_ modeRaw: String) async {
    do {
      try await client.setVirtualDeviceMode(modeRaw)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func refreshOutputMode() async {
    do {
      outputMode = try await client.getOutputMode()
    } catch {
      // Daemon may be down; keep last known value.
    }
  }

  func setOutputMode(_ mode: String) async {
    do {
      try await client.setOutputMode(mode)
      await refreshOutputMode()
    } catch {
      daemonError = formatDaemonError(error)
    }
  }

  func runVirtualDeviceSelfTest(seconds: Int = 5) async {
    do {
      virtualDeviceSelfTest = try await client.runVirtualDeviceSelfTest(seconds: seconds)
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
      virtualDeviceSelfTest = nil
    }
  }

  func refreshVirtualDeviceDiagnostics() async {
    do {
      virtualDeviceDiagnostics = try await client.getVirtualDeviceDiagnostics()
    } catch {
      daemonError = formatDaemonError(error)
      virtualDeviceDiagnostics = nil
    }
  }

  private func formatDaemonError(_ error: Error) -> String {
    let ns = error as NSError
    // Common case: NSXPCConnection was invalidated because launchd killed/restarted the daemon.
    if ns.domain == NSCocoaErrorDomain && ns.code == 4099 {
      if let h = daemonHealth, h.isInefficientKillLoop {
        let runs = h.runs.map { "\($0)" } ?? "unknown"
        return "Daemon was killed by launchd (reason: inefficient, runs=\(runs)). Restart or reinstall the daemon."
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
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      daemonConnected = true
      inputMonitoring = status.inputMonitoring
      devices = status.connectedDevices.map { DeviceViewModel(from: $0) }
      userSpaceVirtualDeviceEnabled = status.userSpaceVirtualDeviceEnabled ?? false
      userSpaceVirtualDeviceStatus = status.userSpaceVirtualDeviceStatus ?? "unknown"
      virtualDeviceMode = status.virtualDeviceMode ?? VirtualDeviceMode.auto.rawValue
      if let eff = status.effectiveOutputMode { outputMode = eff }
    } catch {
      daemonConnected = false
      devices = []
      client.disconnect()
      // Daemon unreachable - fall back to checking this process's own permissions
      // so UI shows something useful rather than stale "unknown".
      inputMonitoring = "\(await permissionManager.checkAccess())"
      // Keep last-known virtual device state. Resetting these makes the UI flip toggles
      // during transient daemon restarts / XPC disconnects.
    }
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
