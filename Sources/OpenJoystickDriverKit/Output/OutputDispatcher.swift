import Foundation

/// Takes parsed controller events and sends them to an output target.
///
/// Implement this protocol to decide what happens when a button is pressed
/// or a stick is moved. The built-in conformances are
/// ``CGEventOutputDispatcher`` (posts macOS keyboard/mouse events) and
/// ``LoggingOutputDispatcher`` (prints events for debugging).
public protocol OutputDispatcher: AnyObject, Sendable {
  /// Receives a batch of events from one controller and writes them to the output.
  ///
  /// Called by ``DevicePipeline`` every time the parser produces new events.
  /// - Parameters:
  ///   - events: The controller events to process.
  ///   - identifier: Which controller the events came from.
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async
}
