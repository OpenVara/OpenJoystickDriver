import Foundation

/// Per-device transport configuration resolved from controller profiles.
public struct DeviceTransportProfile: Equatable, Sendable {
  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

  public init(
    inputEndpoint: UInt8,
    outputEndpoint: UInt8,
    needsSetConfiguration: Bool,
    postHandshakeSettleNanoseconds: UInt64 = 0
  ) {
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleNanoseconds = postHandshakeSettleNanoseconds
  }

  public static let gipDefault = Self(
    inputEndpoint: 0x82, outputEndpoint: 0x02, needsSetConfiguration: false)
}

/// Controller protocol family/variant used for long-term compatibility metadata.
public enum ControllerProtocolVariant: String, Sendable {
  case xboxOriginal
  case xbox360
  case xbox360Wireless
  case xboxOne
  case dualShock3
  case dualShock4
  case genericHID
  case unknown
}

/// Stable mapping flags modeled after Linux xpad's per-device quirks.
public struct ControllerMappingOptions: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let dpadToButtons = Self(rawValue: 1 << 0)
  public static let triggersToButtons = Self(rawValue: 1 << 1)
  public static let sticksToNull = Self(rawValue: 1 << 2)
  public static let shareButton = Self(rawValue: 1 << 3)
  public static let paddles = Self(rawValue: 1 << 4)
  public static let profileButton = Self(rawValue: 1 << 5)
  public static let shareOffset = Self(rawValue: 1 << 6)

  public var names: [String] {
    var result: [String] = []
    if contains(.dpadToButtons) { result.append("dpadToButtons") }
    if contains(.triggersToButtons) { result.append("triggersToButtons") }
    if contains(.sticksToNull) { result.append("sticksToNull") }
    if contains(.shareButton) { result.append("shareButton") }
    if contains(.paddles) { result.append("paddles") }
    if contains(.profileButton) { result.append("profileButton") }
    if contains(.shareOffset) { result.append("shareOffset") }
    return result
  }
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Sendable {
  public let parserName: String
  public let virtualProfile: VirtualDeviceProfile
  public let transportProfile: DeviceTransportProfile
  public let protocolVariant: ControllerProtocolVariant
  public let mappingFlags: [String]
  public let mappingOptions: ControllerMappingOptions
  public let preferredBackends: [VirtualControllerBackendID]
}

/// Loads and caches VID:PID -> runtime profiles from bundled controller profiles.
struct DeviceCatalog: Sendable {
  /// Maps "VID:PID" strings to parser names (e.g. "GIP", "DS4").
  let entries: [String: String]

  /// Maps "VID:PID" strings to virtual profile keys (e.g. "xboxOneS").
  let profileEntries: [String: String]

  /// Maps "VID:PID" strings to per-device transport overrides.
  let transportEntries: [String: DeviceTransportProfile]

  /// Maps "VID:PID" strings to source-backed protocol variants.
  let protocolVariants: [String: ControllerProtocolVariant]

  /// Maps "VID:PID" strings to mapping quirks.
  let mappingOptions: [String: ControllerMappingOptions]

  /// Maps "VID:PID" strings to protocol-specific mapping/feature flag names.
  let mappingFlags: [String: [String]]

  /// Maps "VID:PID" strings to preferred output backends.
  let backendPreferences: [String: [VirtualControllerBackendID]]

  init() {
    let loadedEntries = Self.loadProfileEntries()
    if !loadedEntries.isEmpty {
      var map: [String: String] = [:]
      var profiles: [String: String] = [:]
      var transports: [String: DeviceTransportProfile] = [:]
      var variants: [String: ControllerProtocolVariant] = [:]
      var mappings: [String: ControllerMappingOptions] = [:]
      var flags: [String: [String]] = [:]
      var backends: [String: [VirtualControllerBackendID]] = [:]
      for entry in loadedEntries {
        let key = "\(entry.vendorId):\(entry.productId)"
        map[key] = entry.parser
        profiles[key] = entry.virtualProfile
        transports[key] = entry.transportProfile
        variants[key] = entry.protocolVariant
        mappings[key] = entry.mappingOptions
        flags[key] = entry.mappingFlags
        backends[key] = entry.preferredBackends
      }
      entries = map
      profileEntries = profiles
      transportEntries = transports
      protocolVariants = variants
      mappingOptions = mappings
      mappingFlags = flags
      backendPreferences = backends
    } else {
      print("[DeviceCatalog] Could not load controller profiles - using built-in fallbacks")
      entries = ["13623:4112": "GIP", "1356:1476": "DS4", "1356:2508": "DS4"]
      profileEntries = [:]
      transportEntries = [:]
      protocolVariants = [:]
      mappingOptions = [:]
      mappingFlags = [:]
      backendPreferences = [:]
    }
  }

  func parserName(for identifier: DeviceIdentifier) -> String {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return entries[key] ?? "GenericHID"
  }

  /// Returns the virtual device profile for a physical device.
  ///
  /// Looks up the `output.virtual_profile` field from controller profiles by VID:PID.
  /// Falls back to `.default` (Xbox One S) for unknown devices.
  func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    guard let profileKey = profileEntries[key] else { return .default }
    switch profileKey {
    case "xboxOneS": return .xboxOneS
    default: return .default
    }
  }

  /// Returns transport profile for a device, falling back to GIP defaults.
  func transportProfile(for identifier: DeviceIdentifier) -> DeviceTransportProfile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return transportEntries[key] ?? .gipDefault
  }

  func runtimeProfile(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
    let key = "\(identifier.vendorID):\(identifier.productID)"
    return DeviceRuntimeProfile(
      parserName: parserName(for: identifier),
      virtualProfile: virtualProfile(for: identifier),
      transportProfile: transportProfile(for: identifier),
      protocolVariant: protocolVariants[key] ?? defaultProtocolVariant(for: identifier),
      mappingFlags: mappingFlags[key] ?? mappingOptions[key]?.names ?? [],
      mappingOptions: mappingOptions[key] ?? [],
      preferredBackends: backendPreferences[key] ?? [.driverKitHID, .userSpaceHID]
    )
  }

  private static func loadProfileEntries() -> [RuntimeEntry] {
    let profileURLs =
      (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Controllers") ?? [])
      + (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
    let decoder = JSONDecoder()
    let profiles = profileURLs.compactMap { url -> RuntimeEntry? in
      guard let data = try? Data(contentsOf: url),
        let decoded = try? decoder.decode(ProfileDeviceEntry.self, from: data)
      else {
        return nil
      }
      return RuntimeEntry(profile: decoded)
    }
    if !profiles.isEmpty { return profiles }
    return []
  }

  private static func mappingOptions(from flags: [String]?) -> ControllerMappingOptions {
    var options: ControllerMappingOptions = []
    for flag in flags ?? [] {
      switch flag {
      case "dpadToButtons": options.insert(.dpadToButtons)
      case "triggersToButtons": options.insert(.triggersToButtons)
      case "sticksToNull": options.insert(.sticksToNull)
      case "shareButton": options.insert(.shareButton)
      case "paddles": options.insert(.paddles)
      case "profileButton": options.insert(.profileButton)
      case "shareOffset": options.insert(.shareOffset)
      default: break
      }
    }
    return options
  }

  private func defaultProtocolVariant(for identifier: DeviceIdentifier) -> ControllerProtocolVariant {
    switch parserName(for: identifier) {
    case "GIP": return .xboxOne
    case "DS4": return .dualShock4
    case "Xbox360": return .xbox360
    case "GenericHID": return .genericHID
    default: return .unknown
    }
  }

  // MARK: - Internal JSON shape

  private struct RuntimeEntry {
    let vendorId: Int
    let productId: Int
    let parser: String
    let virtualProfile: String
    let transportProfile: DeviceTransportProfile
    let protocolVariant: ControllerProtocolVariant
    let mappingFlags: [String]
    let mappingOptions: ControllerMappingOptions
    let preferredBackends: [VirtualControllerBackendID]

    init?(profile: ProfileDeviceEntry) {
      vendorId = profile.identity.vendorId
      productId = profile.identity.productId
      parser = profile.protocolConfig.driver
      virtualProfile = profile.output.virtualProfile
      protocolVariant =
        ControllerProtocolVariant(rawValue: profile.protocolConfig.variant) ?? .unknown
      mappingFlags = profile.protocolConfig.mappingFlags ?? []
      mappingOptions = DeviceCatalog.mappingOptions(from: mappingFlags)
      preferredBackends = profile.output.preferredBackends.compactMap(
        VirtualControllerBackendID.init(rawValue:)
      )

      let endpoints = profile.input.usb.endpoints
      let inEndpoint = endpoints?.inEndpoint ?? 0x82
      let outEndpoint = endpoints?.outEndpoint ?? 0x02
      guard (0...255).contains(inEndpoint), (0...255).contains(outEndpoint) else { return nil }
      let settleMs = profile.input.usb.postHandshakeSettleMs ?? 0
      guard settleMs >= 0 else { return nil }
      let needsSetConfiguration = profile.input.usb.configuration == "set1BeforeClaim"
      let settleNs = UInt64(settleMs) * 1_000_000
      transportProfile = DeviceTransportProfile(
        inputEndpoint: UInt8(inEndpoint),
        outputEndpoint: UInt8(outEndpoint),
        needsSetConfiguration: needsSetConfiguration,
        postHandshakeSettleNanoseconds: settleNs
      )
    }
  }

  private struct ProfileDeviceList: Decodable {
    let controllers: [ProfileDeviceEntry]
  }

  private struct ProfileDeviceEntry: Decodable {
    let identity: Identity
    let input: Input
    let protocolConfig: ProtocolConfig
    let output: Output

    enum CodingKeys: String, CodingKey {
      case identity
      case input
      case protocolConfig = "protocol"
      case output
    }

    struct Identity: Decodable {
      let vendorId: Int
      let productId: Int

      enum CodingKeys: String, CodingKey {
        case vendorId = "vendor_id"
        case productId = "product_id"
      }
    }

    struct Input: Decodable {
      let usb: USB

      struct USB: Decodable {
        let configuration: String?
        let postHandshakeSettleMs: Int?
        let endpoints: Endpoints?

        enum CodingKeys: String, CodingKey {
          case configuration
          case postHandshakeSettleMs = "post_handshake_settle_ms"
          case endpoints
        }
      }

      struct Endpoints: Decodable {
        let inEndpoint: Int
        let outEndpoint: Int

        enum CodingKeys: String, CodingKey {
          case inEndpoint = "in"
          case outEndpoint = "out"
        }
      }
    }

    struct ProtocolConfig: Decodable {
      let driver: String
      let variant: String
      let mappingFlags: [String]?

      enum CodingKeys: String, CodingKey {
        case driver
        case variant
        case mappingFlags = "mapping_flags"
      }
    }

    struct Output: Decodable {
      let virtualProfile: String
      let preferredBackends: [String]

      enum CodingKeys: String, CodingKey {
        case virtualProfile = "virtual_profile"
        case preferredBackends = "preferred_backends"
      }
    }
  }
}
