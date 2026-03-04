import Foundation

/// Receives parsed controller events and
/// dispatches them to to output layer.
/// Implementations: CGEventOutputDispatcher (production),
/// LoggingOutputDispatcher (development / hardware validation).
public protocol OutputDispatcher: AnyObject, Sendable {
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async
}
