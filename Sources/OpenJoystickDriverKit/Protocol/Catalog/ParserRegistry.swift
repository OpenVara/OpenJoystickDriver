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
    let endpoints = catalog.endpointConfig(for: identifier)
    switch catalog.parserName(for: identifier) {
    case "GIP": return GIPParser(endpointConfig: endpoints)
    case "DS4": return DS4Parser()
    default: return GenericHIDParser(identifier: identifier)
    }
  }

  /// Returns USB endpoint config for given device identifier.
  public func endpointConfig(for identifier: DeviceIdentifier) -> USBEndpointConfig {
    catalog.endpointConfig(for: identifier)
  }

  /// Returns the physical transport profile for given device identifier.
  public func transportProfile(for identifier: DeviceIdentifier) -> DeviceTransportProfile {
    catalog.transportProfile(for: identifier)
  }

  /// Returns the complete runtime profile for a physical controller model.
  public func runtimeProfile(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
    catalog.runtimeProfile(for: identifier)
  }

  /// Returns the suggested virtual device identity for compatibility mode.
  ///
  /// Used only when the user explicitly opts into spoofing IDs for picky consumers.
  public func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    catalog.virtualProfile(for: identifier)
  }
}
