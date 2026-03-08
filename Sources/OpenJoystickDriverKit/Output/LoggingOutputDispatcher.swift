import Foundation

/// OutputDispatcher that logs controller events to debug output.
/// Used for hardware validation and testing. For production
/// output use DextOutputDispatcher or IOHIDVirtualOutputDispatcher.
public final class LoggingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  // Suppression is accepted but ignored — this is a dev-only dispatcher.
  public var suppressOutput = false

  public init() {}

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    for event in events {
      print("[Output] " + "\(identifier.vendorID):\(identifier.productID)" + " -> \(event)")
    }
  }
}
