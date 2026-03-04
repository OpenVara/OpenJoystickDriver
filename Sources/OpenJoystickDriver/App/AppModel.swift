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

  /// Parse daemon description string of form:
  /// "NAME (VID:X PID:X PARSER [USB])"
  static func parse(description: String) -> Self? {
    guard
      let parenRange = description.range(
        of: #"\(VID:(\d+) PID:(\d+) (\w+)"#,
        options: .regularExpression
      )
    else {
      return Self(id: description, name: description, vendorID: 0, productID: 0, parser: "Unknown")
    }

    let parenStr = String(description[parenRange])
    let parts = parenStr.replacingOccurrences(of: "(", with: "").components(separatedBy: " ")
    // parts: ["VID:X", "PID:X", "PARSER", ...]
    let vid = parts.first { $0.hasPrefix("VID:") }.flatMap { UInt16($0.dropFirst(4)) } ?? 0
    let pid = parts.first { $0.hasPrefix("PID:") }.flatMap { UInt16($0.dropFirst(4)) } ?? 0
    let parser = parts.first { !$0.hasPrefix("VID:") && !$0.hasPrefix("PID:") } ?? "Unknown"

    // Name is everything before opening paren
    let name: String
    if let idx = description.firstIndex(of: "(") {
      name = String(description[..<idx]).trimmingCharacters(in: .whitespaces)
    } else {
      name = description
    }

    return Self(
      id: description,
      name: name.isEmpty ? description : name,
      vendorID: vid,
      productID: pid,
      parser: parser
    )
  }
}

/// Central observable model for GUI.
/// Polls daemon via XPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  @Published var daemonConnected = false
  @Published var daemonInstalled = false
  @Published var daemonError: String?
  @Published var devices: [DeviceViewModel] = []
  @Published var inputMonitoring = "unknown"
  @Published var accessibility = "unknown"
  @Published var profiles: [Profile] = []

  private let client = XPCClient()
  private var pollTask: Task<Void, Never>?

  func start() async {
    client.connect()
    refreshDaemonStatus()
    await poll()
    startPolling()
  }

  func refreshDaemonStatus() { daemonInstalled = DaemonManager.isInstalled }

  func installDaemon() async {
    daemonError = nil
    guard let execURL = Bundle.main.executableURL else {
      daemonError = "Cannot locate app executable."
      return
    }
    let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent(
      "OpenJoystickDriverDaemon"
    )
    do {
      let task = Task.detached { try DaemonManager.install(daemonExecutable: daemonURL) }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    refreshDaemonStatus()
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
      debugPrint("[AppModel] refreshProfiles error: \(error)")
    }
  }

  private func poll() async {
    refreshDaemonStatus()
    do {
      let status = try await client.getStatus()
      daemonConnected = true
      inputMonitoring = status.inputMonitoring
      accessibility = status.accessibility
      devices = status.connectedDevices.compactMap(DeviceViewModel.parse(description:))
    } catch {
      daemonConnected = false
      devices = []
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
