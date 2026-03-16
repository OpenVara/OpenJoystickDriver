import Foundation

/// Tracks per-command sequence numbers for the GIP (Xbox One) protocol.
///
/// GIP packets include a sequence number that increments independently for
/// each command type. The controller uses these to detect missed or
/// out-of-order packets. Counters wrap around at 255.
public struct GIPSequencer: Sendable {
  private var counters: [UInt8: UInt8] = [:]

  /// Creates a new GIPSequencer with all counters at zero.
  public init() {}

  /// Returns the next sequence number for the given command ID and advances the counter.
  ///
  /// Wraps from 255 back to 0.
  public mutating func next(for commandID: UInt8) -> UInt8 {
    let current = counters[commandID, default: 0]
    counters[commandID] = current &+ 1
    return current
  }

  /// Resets the sequence counter for a specific command back to zero.
  public mutating func reset(commandID: UInt8) { counters[commandID] = 0 }
}
