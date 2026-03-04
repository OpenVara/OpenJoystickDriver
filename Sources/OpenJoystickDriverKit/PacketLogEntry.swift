import Foundation

/// One recorded USB packet shown in the Developer tab packet log.
///
/// Stored in a ring buffer inside ``DevicePipeline`` (up to 200 entries).
public struct PacketLogEntry: Codable, Sendable {
  /// Seconds since reference date when the packet was captured.
  public let timestamp: TimeInterval
  /// Transfer direction: `"rx"` for incoming, `"tx"` for outgoing.
  public let direction: String
  /// Packet payload as a hex-encoded string (e.g. `"05 20 00 01 00"`).
  public let hex: String
  /// Number of bytes in the packet.
  public let length: Int
}
