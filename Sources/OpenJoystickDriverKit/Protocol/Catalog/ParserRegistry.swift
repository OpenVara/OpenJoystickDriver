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
    let runtimeProfile = catalog.runtimeProfile(for: identifier)
    let transportProfile = runtimeProfile.transportProfile
    switch catalog.parserName(for: identifier) {
    case "GIP":
      return GIPParser(
        transportProfile: transportProfile,
        startupPackets: runtimeProfile.gipStartupPackets
      )
    case "DS4": return DS4Parser()
    case "Xbox360": return Xbox360Parser(outEndpoint: transportProfile.outputEndpoint)
    default: return GenericHIDParser(identifier: identifier)
    }
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
