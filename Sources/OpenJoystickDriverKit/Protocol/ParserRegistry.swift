import Foundation

/// Dispatches controllers to appropriate parser
/// by VID/PID lookup.
public final class ParserRegistry: Sendable {
  private let catalog = DeviceCatalog()

  /// Creates a new ParserRegistry.
  public init() {}

  /// Returns parser name for given device identifier.
  public func parserName(for identifier: DeviceIdentifier) -> String {
    catalog.parserName(for: identifier)
  }

  /// Returns parser for given device identifier.
  public func parser(for identifier: DeviceIdentifier) -> any InputParser {
    switch catalog.parserName(for: identifier) {
    case "GIP": return GIPParser()
    case "DS4": return DS4Parser()
    case "XB360": return XB360Parser()
    default: return GenericHIDParser(identifier: identifier)
    }
  }
}
