import Foundation

/// OutputDispatcher that logs controller events to debug output.
/// Used for hardware validation and testing. For production
/// output use CGEventOutputDispatcher.
public final class LoggingOutputDispatcher: OutputDispatcher, Sendable {
  public init() {}

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    for event in events {
      print("[Output] " + "\(identifier.vendorID):\(identifier.productID)" + " -> \(event)")
    }
  }
}
