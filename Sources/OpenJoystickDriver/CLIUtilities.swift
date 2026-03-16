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
