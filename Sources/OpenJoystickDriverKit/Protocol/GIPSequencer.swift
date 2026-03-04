import Foundation

/// Manages per-command-ID sequence numbers for  GIP protocol.
/// Each command type increments its own counter independently.
public struct GIPSequencer: Sendable {
  private var counters: [UInt8: UInt8] = [:]

  public init() {}

  /// Returns next sequence number for given command ID,
  /// wrapping at 255.
  public mutating func next(for commandID: UInt8) -> UInt8 {
    let current = counters[commandID, default: 0]
    counters[commandID] = current &+ 1
    return current
  }

  /// Reset sequence counter for specific command.
  public mutating func reset(commandID: UInt8) { counters[commandID] = 0 }
}
