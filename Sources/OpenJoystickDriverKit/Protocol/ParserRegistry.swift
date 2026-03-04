import Foundation

/// Dispatches controllers to appropriate parser
/// by VID/PID lookup.
public final class ParserRegistry: Sendable {
  private let catalog = DeviceCatalog()

  public init() {}

  /// Returns parser for given device identifier.
  public func parser(for identifier: DeviceIdentifier) -> any InputParser {
    switch catalog.parserName(for: identifier) {
    case "GIP": return GIPParser()
    case "DS4": return DS4Parser()
    default: return GenericHIDParser(identifier: identifier)
    }
  }
}
