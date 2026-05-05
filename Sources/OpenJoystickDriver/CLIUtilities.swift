import Foundation

/// Timeout for XPC calls from CLI - keeps commands
/// responsive when daemon is not running.
let xpcCallTimeoutSeconds: Double = 0.5

/// Blocks current thread until `block` completes.
///
/// Safe for CLI use only - never call from main actor or async context.
func runSync(_ block: @Sendable @escaping () async -> Void) {
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    await block()
    semaphore.signal()
  }
  semaphore.wait()
}

/// Blocks current thread until `block` completes, returning its value.
///
/// Safe for CLI use only - never call from main actor or async context.
func runSyncResult<T: Sendable>(_ block: @Sendable @escaping () async -> T) -> T {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: T?
  Task {
    result = await block()
    semaphore.signal()
  }
  semaphore.wait()
  guard let value = result else {
    fatalError("runSyncResult: block completed without setting result")
  }
  return value
}

/// Blocks current thread until `block` completes or the timeout expires.
///
/// Returns nil on timeout. Safe for CLI status probes that must not hang when
/// the daemon connection is invalidated without a reply.
func runSyncResult<T: Sendable>(
  timeout seconds: Double,
  _ block: @Sendable @escaping () async -> T
) -> T? {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: T?
  Task {
    result = await block()
    semaphore.signal()
  }
  guard semaphore.wait(timeout: .now() + seconds) == .success else { return nil }
  return result
}

/// Ensures the CLI is executed from an app bundle installed under `/Applications`.
///
/// This repo's LaunchAgent plist uses an absolute ProgramArguments path under
/// `/Applications/OpenJoystickDriver.app/...` for reliable provisioning profile resolution.
func requireApplicationsBundleOrExit() {
  let path = Bundle.main.bundlePath
  guard path.hasPrefix("/Applications/") else {
    print("ERROR: This command must be run from the /Applications-installed app bundle.")
    print("  Current bundle: \(path)")
    print("  Fix: run: /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless <command>")
    exit(1)
  }
}

/// Ensures the app bundle is validly signed.
///
/// This catches the common dev failure mode where a `.dext` is copied into the app bundle
/// after signing, which breaks the signature and causes SMAppService registration to fail.
func requireValidBundleSignatureOrExit(action: String) {
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
    print("ERROR: \(action) failed: could not run codesign verification: \(error.localizedDescription)")
    exit(1)
  }
  process.waitUntilExit()
  let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    if out.contains("a sealed resource is missing or invalid") {
      print("ERROR: \(action) failed: this app bundle's signature is INVALID (modified after signing).")
      print("")
      print("Fix:")
      print("  1) Run: ./scripts/ojd rebuild-fast dev")
      print("  2) Then re-run: /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless \(action.lowercased())")
      print("")
      print("Diagnostic command:")
      print("  /usr/bin/codesign --verify --deep --strict --verbose=2 \(appPath)")
      exit(1)
    }
    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    print("ERROR: \(action) failed: app signature verification failed:")
    if trimmed.isEmpty {
      print("  (no output)")
    } else {
      print(trimmed)
    }
    exit(1)
  }
}
