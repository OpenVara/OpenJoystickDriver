import Foundation

/// Optional output-dispatcher hook for controller lifecycle events.
///
/// `DevicePipeline` calls this when a physical controller pipeline stops so output backends
/// can tear down any per-controller virtual devices (for example, a per-controller
/// IOHIDUserDevice in Compatibility mode).
public protocol ControllerLifecycleListener: AnyObject, Sendable {
  func controllerDidStop(_ identifier: DeviceIdentifier) async
}

