import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// Wraps non-Sendable XPC reply closure so it can cross Task boundary.
///
/// Safe because XPC dispatches reply blocks on its own serial queue.
private struct SendableReply<T>: @unchecked Sendable { let call: (T) -> Void }

/// NSXPCListener server that exposes DeviceManager state to GUI/CLI over Mach IPC.
///
/// Call start() once; listener lives for process lifetime.
/// - Note: @unchecked Sendable: XPCService is thread-safe -
///   actor-isolated DeviceManager/PermissionManager handle
///   their own synchronization; reply blocks are dispatched
///   by XPC runtime.
@objc
public final class XPCService: NSObject, NSXPCListenerDelegate, OpenJoystickDriverXPCProtocol,
  @unchecked Sendable
{
  private let deviceManager: DeviceManager
  private let permissionManager: PermissionManager
  private let dispatcher: CompositeOutputDispatcher
  private let dextDispatcher: DextOutputDispatcher
  private let userSpaceLock = NSLock()
  private var userSpaceDispatcher: UserSpaceOutputDispatcher?
  private var userSpaceEnabled: Bool
  private var userSpaceStatus: String = "off"
  private var compatibilityIdentity: CompatibilityIdentity
  private var virtualDeviceMode: VirtualDeviceMode
  /// Actual routing mode currently applied.
  private var effectiveOutputMode: CompositeOutputDispatcher.Mode
  private var listener: NSXPCListener?
  private static let userSpaceEnabledDefaultsKey = "UserSpaceVirtualDeviceEnabled"
  private static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"
  private static let outputModeDefaultsKey = "OutputMode"
  private static let virtualDeviceModeDefaultsKey = "VirtualDeviceMode"

  /// Creates an XPCService backed by the given device manager, permission manager, and output dispatcher.
  public init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompositeOutputDispatcher,
    dextDispatcher: DextOutputDispatcher
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.dextDispatcher = dextDispatcher
    self.userSpaceEnabled = UserDefaults.standard.bool(forKey: Self.userSpaceEnabledDefaultsKey)
    let savedCompat = UserDefaults.standard.string(forKey: Self.compatibilityIdentityDefaultsKey)
    self.compatibilityIdentity = CompatibilityIdentity(rawValue: savedCompat ?? "") ?? .sdlMacOS
    let savedVirtual = UserDefaults.standard.string(forKey: Self.virtualDeviceModeDefaultsKey)
    if let raw = savedVirtual, let mode = VirtualDeviceMode(rawValue: raw) {
      self.virtualDeviceMode = mode
    } else {
      // Migration from previous routing keys (OutputMode + userSpaceEnabled).
      let savedMode = UserDefaults.standard.string(forKey: Self.outputModeDefaultsKey)
      let parsed = CompositeOutputDispatcher.Mode(rawValue: savedMode ?? "")
      if parsed == .both {
        self.virtualDeviceMode = .both
      } else if userSpaceEnabled {
        self.virtualDeviceMode = .compatUserSpace
      } else {
        // Default to Compatibility-first so SDL/IOKit apps work without requiring a reboot.
        self.virtualDeviceMode = .compatUserSpace
      }
    }
    self.effectiveOutputMode = .primaryOnly

    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDextUnstable(_:)),
      name: DextOutputDispatcher.dextUnstableNotification,
      object: nil
    )

    applyMode(virtualDeviceMode)
  }

  private func applyMode(_ mode: VirtualDeviceMode) {
    virtualDeviceMode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: Self.virtualDeviceModeDefaultsKey)

    switch mode {
    case .auto:
      // Prefer DriverKit, but allow an automatic one-way fall back to user-space if DriverKit
      // output becomes unstable (during sysext replacement/upgrade, or if the dext isn't ready).
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
    case .driverKit:
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
    case .compatUserSpace:
      // Compatibility is user-requested. Do not rewrite the requested mode on failures.
      //
      // If user-space creation fails, keep DriverKit enabled as a fallback but keep the
      // requested mode as Compatibility and show an explicit error string.
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        dextDispatcher.setCompatibilitySeizeEnabled(false)
        dextDispatcher.setEnabled(false)
        effectiveOutputMode = .secondaryOnly
        dispatcher.setMode(.secondaryOnly)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.secondaryOnly.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
      } else {
        dextDispatcher.setCompatibilitySeizeEnabled(false)
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.primaryOnly.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
        if !userSpaceStatus.hasPrefix("error:") {
          userSpaceStatus =
            "error: Compatibility backend failed to start. Still using DriverKit output."
        } else {
          userSpaceStatus += " (still using DriverKit output)"
        }
      }
    case .both:
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      if compatibilityIdentity.disablesDriverKitMirror {
        _ = setUserSpaceVirtualDeviceEnabledInternal(false)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        userSpaceStatus =
          "off (\(compatibilityIdentity.rawValue) Compatibility disabled while DriverKit output is active)"
        return
      }
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        effectiveOutputMode = .both
        dispatcher.setMode(.both)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.both.rawValue, forKey: Self.outputModeDefaultsKey)
      } else {
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
        if !userSpaceStatus.hasPrefix("error:") {
          userSpaceStatus =
            "error: Compatibility backend failed to start. Still using DriverKit output."
        } else {
          userSpaceStatus += " (still using DriverKit output)"
        }
      }
    }
  }

  /// Register Mach service and start accepting connections.
  public func start() {
    let xpcListener = NSXPCListener(machServiceName: xpcServiceName)
    xpcListener.delegate = self
    xpcListener.resume()
    listener = xpcListener
    print("[XPCService] Listening on \(xpcServiceName)")
  }

  // MARK: - NSXPCListenerDelegate

  /// Configures and resumes each incoming XPC connection.
  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: OpenJoystickDriverXPCProtocol.self)
    connection.exportedObject = self
    connection.resume()
    print("[XPCService] Accepted new connection")
    return true
  }

  // MARK: - OpenJoystickDriverXPCProtocol

  /// Returns a list of connected device descriptions.
  public func listDevices(reply: @escaping ([String]) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let devices = await dm.connectedDeviceDescriptions()
      let strings = devices.map { d in
        let sn = d.serialNumber ?? "none"
        let mappings = d.mappingFlags.isEmpty ? "none" : d.mappingFlags.joined(separator: ",")
        let backends = d.preferredBackends.isEmpty ? "none" : d.preferredBackends.joined(separator: ",")
        return "\(d.name) (VID:\(d.vendorID)" + " PID:\(d.productID) \(d.parser)"
          + " [\(d.connection)] SN:\(sn))"
          + " protocol=\(d.protocolVariant)"
          + " endpoints=in:0x\(String(d.inputEndpoint, radix: 16)) out:0x\(String(d.outputEndpoint, radix: 16))"
          + " setConfig=\(d.needsSetConfiguration)"
          + " settleMs=\(d.postHandshakeSettleMs)"
          + " mappings=\(mappings)"
          + " backends=\(backends)"
      }
      callback.call(strings)
    }
  }

  /// Returns the current daemon status including input monitoring state and connected devices.
  public func getStatus(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    let pm = permissionManager
    Task {
      let inputState = await pm.inputMonitoringState
      let devices = await dm.connectedDeviceDescriptions()
      let userEnabled = userSpaceEnabled
      let userStatus = currentUserSpaceStatus()
      let payload = XPCStatusPayload(
        inputMonitoring: "\(inputState)",
        connectedDevices: devices,
        userSpaceVirtualDeviceEnabled: userEnabled,
        userSpaceVirtualDeviceStatus: userStatus,
        virtualDeviceMode: virtualDeviceMode.rawValue,
        effectiveOutputMode: effectiveOutputMode.rawValue,
        compatibilityIdentity: compatibilityIdentity.rawValue
      )
      do {
        let data = try JSONEncoder().encode(payload)
        callback.call(data)
      } catch {
        print("[XPCService] getStatus encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getDeviceInputState(vendorID: Int, productID: Int, reply: @escaping (Data?) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let state = await dm.inputState(for: identifier)
      callback.call(try? JSONEncoder().encode(state))
    }
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let log = await dm.packetLog(for: identifier)
      do {
        let data = try JSONEncoder().encode(log)
        callback.call(data)
      } catch {
        print("[XPCService] getPacketLog encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    left: Int,
    right: Int,
    lt: Int,
    rt: Int,
    durationMs: Int,
    reply: @escaping (Bool) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let ok = await dm.sendRumble(
        for: identifier,
        left: UInt8(clamping: left),
        right: UInt8(clamping: right),
        lt: UInt8(clamping: lt),
        rt: UInt8(clamping: rt),
        durationMs: durationMs
      )
      callback.call(ok)
    }
  }

  /// Enables or disables virtual output suppression and reports success.
  public func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void) {
    dispatcher.suppressOutput = suppress
    reply(true)
  }

  public func setVirtualDeviceMode(_ modeRaw: String, reply: @escaping (Bool) -> Void) {
    guard let mode = VirtualDeviceMode(rawValue: modeRaw) else {
      reply(false)
      return
    }
    applyMode(mode)
    reply(true)
  }

  public func getVirtualDeviceMode(reply: @escaping (String) -> Void) {
    reply(virtualDeviceMode.rawValue)
  }

  public func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool, reply: @escaping (Bool) -> Void) {
    // Legacy API: map to virtual device modes.
    if enabled {
      applyMode(.compatUserSpace)
    } else {
      applyMode(.driverKit)
    }
    reply(true)
  }

  public func getUserSpaceVirtualDeviceEnabled(reply: @escaping (Bool) -> Void) {
    reply(userSpaceEnabled)
  }

  public func getUserSpaceVirtualDeviceStatus(reply: @escaping (String) -> Void) {
    reply(currentUserSpaceStatus())
  }

  public func setCompatibilityIdentity(_ raw: String, reply: @escaping (Bool) -> Void) {
    guard let id = CompatibilityIdentity(rawValue: raw) else { reply(false); return }
    // Transactional switch:
    // - If user-space is enabled, do not tear down the current device until the new one is ready.
    // - If creation fails, keep the existing device alive and do not change the persisted identity.
    let ok = userSpaceLock.withLock { () -> Bool in
      if userSpaceEnabled, let old = userSpaceDispatcher {
        do {
          let (newDispatcher, newStatus) = try buildUserSpaceDispatcher(identity: id)
          dispatcher.setSecondary(newDispatcher)
          userSpaceDispatcher = newDispatcher
          userSpaceStatus = newStatus
          compatibilityIdentity = id
          UserDefaults.standard.set(id.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
          old.close()
          primeUserSpaceDevices(newDispatcher)
          return true
        } catch {
          if !userSpaceStatus.hasPrefix("error:") {
            userSpaceStatus =
              "error: Failed to switch Compatibility identity (\(id.rawValue)). Kept previous Compatibility device running. \(error)"
          } else {
            userSpaceStatus += " (kept previous Compatibility device running)"
          }
          return false
        }
      }

      // If user-space isn't currently enabled, just persist the choice. It will be applied on next enable.
      compatibilityIdentity = id
      UserDefaults.standard.set(id.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
      return true
    }
    if ok && id.disablesDriverKitMirror && virtualDeviceMode == .both {
      applyMode(.both)
    }
    reply(ok)
  }

  public func getCompatibilityIdentity(reply: @escaping (String) -> Void) {
    reply(compatibilityIdentity.rawValue)
  }

  public func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      let enabled = userSpaceEnabled
      let status = currentUserSpaceStatus()
      let mode = effectiveOutputMode
      let devices = VirtualDeviceDiagnostics.enumerateHIDGamepads()
      let stats = dextDispatcher.outputStatsSnapshot()
      let payload = XPCVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: enabled,
        userSpaceVirtualDeviceStatus: status,
        outputMode: mode.rawValue,
        hidGamepads: devices,
        driverKitOutputStats: stats
      )
      do {
        callback.call(try JSONEncoder().encode(payload))
      } catch {
        print("[XPCService] getVirtualDeviceDiagnostics encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func setOutputMode(_ mode: String, reply: @escaping (Bool) -> Void) {
    reply(setOutputModeInternal(mode))
  }

  public func getOutputMode(reply: @escaping (String) -> Void) {
    // Legacy API: return the *effective* output routing, not the requested mode.
    // This prevents UI desync when Auto falls back to user-space.
    reply(effectiveOutputMode.rawValue)
  }

  public func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let secs = max(1, min(30, seconds))
    Task {
      let payload = await runVirtualDeviceSelfTestInternal(seconds: secs)
      do {
        callback.call(try JSONEncoder().encode(payload))
      } catch {
        print("[XPCService] runVirtualDeviceSelfTest encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func resetSettings(reply: @escaping (Bool) -> Void) {
    // Clear persisted keys so the daemon comes up in a known-good baseline.
    UserDefaults.standard.removeObject(forKey: Self.userSpaceEnabledDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.compatibilityIdentityDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.outputModeDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.virtualDeviceModeDefaultsKey)

    userSpaceLock.withLock {
      dispatcher.setSecondary(nil)
      userSpaceDispatcher?.close()
      userSpaceDispatcher = nil
      userSpaceEnabled = false
      userSpaceStatus = "off"
    }

    compatibilityIdentity = .sdlMacOS
    virtualDeviceMode = .compatUserSpace
    effectiveOutputMode = .primaryOnly
    applyMode(.compatUserSpace)
    reply(true)
  }

  // MARK: - Private

  private func buildUserSpaceDispatcher(identity: CompatibilityIdentity) throws -> (UserSpaceOutputDispatcher, String) {
    enum CompatError: Swift.Error, CustomStringConvertible, Sendable {
      case unsupported(String)
      var description: String {
        switch self {
        case .unsupported(let msg):
          return msg
        }
      }
    }

    let compatibilityProfile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let profile = compatibilityProfile.deviceProfile
    let format: any VirtualGamepadReportFormat
    switch identity {
    case .genericHID:
      format = OJDGenericGamepadFormat()
    case .sdlMacOS:
      format = OJDGenericGamepadFormat(includesDpadButtonBits: false)
    case .xoneHID:
      // Xbox One identity for SDL/Steam/PCSX2:
      // - Prefer the physical HID report descriptor exposed by macOS for 045E:02EA (USB).
      //   This makes SDL treat the virtual device as a real Xbox controller.
      // - Fall back to a built-in descriptor if the physical device is not present.
      if let physical = HIDDescriptorReportFormat.copyPhysicalReportDescriptor(
        vendorID: profile.vendorID,
        productID: profile.productID,
        preferredTransport: "USB"
      ) {
        do {
          format = try HIDDescriptorReportFormat(descriptor: physical)
        } catch {
          // If parsing fails on this OS build, fall back to the built-in descriptor.
          format = try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
        }
      } else {
        format = try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
      }
    case .x360HID:
      format = Xbox360XUSBDirectInputReportFormat()
    }

    let ud = try UserSpaceOutputDispatcher(
      profile: profile,
      format: format,
      emitsXboxGuideReport: compatibilityProfile.emitsXboxGuideReport
    )
    return (ud, ud.status)
  }

  private func setUserSpaceVirtualDeviceEnabledInternal(_ enabled: Bool) -> Bool {
    if enabled == userSpaceEnabled {
      if enabled && userSpaceDispatcher == nil {
        // Persisted state says enabled, but the user-space device isn't actually created
        // (common after daemon restart). Fall through to create it.
      } else if !enabled && userSpaceDispatcher != nil {
        // Persisted state says disabled, but dispatcher still exists; fall through to disable.
      } else {
        return true
      }
    }

    if enabled {
      do {
        let (ud, s) = try buildUserSpaceDispatcher(identity: compatibilityIdentity)
        userSpaceLock.withLock {
          userSpaceDispatcher = ud
          dispatcher.setSecondary(ud)
          userSpaceEnabled = true
          userSpaceStatus = s
        }
        UserDefaults.standard.set(true, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[XPCService] Enabled user-space virtual gamepad")
        primeUserSpaceDevices(ud)
        return true
      } catch {
        userSpaceLock.withLock {
          dispatcher.setSecondary(nil)
          userSpaceDispatcher = nil
          userSpaceEnabled = false
          userSpaceStatus = "error: \(error)"
        }
        UserDefaults.standard.set(false, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[XPCService] Failed to enable user-space virtual gamepad: \(error)")
        return false
      }
    } else {
      userSpaceLock.withLock {
        dispatcher.setSecondary(nil)
        userSpaceDispatcher?.close()
        userSpaceDispatcher = nil
        userSpaceEnabled = false
        userSpaceStatus = "off"
      }
      UserDefaults.standard.set(false, forKey: Self.userSpaceEnabledDefaultsKey)
      print("[XPCService] Disabled user-space virtual gamepad")
      return true
    }
  }

  private func setOutputModeInternal(_ modeRaw: String) -> Bool {
    guard let newMode = CompositeOutputDispatcher.Mode(rawValue: modeRaw) else { return false }
    switch newMode {
    case .primaryOnly: applyMode(.driverKit); return true
    case .secondaryOnly: applyMode(.compatUserSpace); return true
    case .both: applyMode(.both); return true
    }
  }

  private func currentUserSpaceStatus() -> String {
    userSpaceLock.withLock {
      userSpaceDispatcher?.status ?? userSpaceStatus
    }
  }

  private func primeUserSpaceDevices(_ ud: UserSpaceOutputDispatcher) {
    let dm = deviceManager
    Task {
      let identifiers = await dm.connectedDeviceIdentifiers()
      guard !identifiers.isEmpty else { return }
      for identifier in identifiers {
        await ud.dispatch(events: [], from: identifier)
      }
      userSpaceLock.withLock {
        if userSpaceDispatcher === ud {
          userSpaceStatus = ud.status
        }
      }
    }
  }

  @objc private func handleDextUnstable(_ note: Notification) {
    // If DriverKit injection is unstable during sysext replacement/upgrade,
    // fall back to user-space-only when possible (no reboot).
    guard virtualDeviceMode == .auto || virtualDeviceMode == .both else { return }
    guard effectiveOutputMode != .secondaryOnly else { return }
    if userSpaceDispatcher == nil {
      guard setUserSpaceVirtualDeviceEnabledInternal(true) else { return }
    }
    effectiveOutputMode = .secondaryOnly
    dispatcher.setMode(.secondaryOnly)
    userSpaceStatus = "on (auto: DriverKit unstable, using user-space only until reboot)"
    print("[XPCService] Auto-fallback: DriverKit unstable -> user-space only")
  }

  private final class SelfTestCounter {
    private let lock = NSLock()
    private(set) var driverKitValueEvents: Int = 0
    private(set) var driverKitReportEvents: Int = 0
    private(set) var userSpaceValueEvents: Int = 0
    private(set) var userSpaceReportEvents: Int = 0

    enum EventKind {
      case value
      case report
    }

    func record(device: IOHIDDevice, kind: EventKind) {
      // IMPORTANT:
      // IOHIDDevice properties can be incomplete during system-extension replacement/upgrade.
      // Prefer IORegistry properties via IOHIDDeviceGetService for reliable identification.
      func strProp(_ key: String) -> String? {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? String
      }
      func intProp(_ key: String) -> Int {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int ?? 0
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
      }

      let ioUserClass = strProp("IOUserClass")
      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let location = intProp(kIOHIDLocationIDKey as String)
      let vid = intProp(kIOHIDVendorIDKey as String)
      let pid = intProp(kIOHIDProductIDKey as String)
      let product = strProp(kIOHIDProductKey as String)
      let manufacturer = strProp(kIOHIDManufacturerKey as String)

      let isUserSpace =
        UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)
        || (ioUserClass == "IOHIDUserDevice")

      let looksLikeOJDVirtual =
        (vid == VirtualDeviceProfile.default.vendorID)
        && (pid == VirtualDeviceProfile.default.productID)
        && (product == VirtualDeviceProfile.default.productName)
        && (manufacturer == VirtualDeviceProfile.default.manufacturer)

      let isDriverKit =
        (serial == VirtualDeviceIdentityConstants.driverKitSerialNumber)
        || (location == Int(VirtualDeviceIdentityConstants.driverKitLocationID))
        || (ioUserClass == "OpenJoystickVirtualHIDDevice")
        || (!isUserSpace && looksLikeOJDVirtual)

      lock.withLock {
        if isDriverKit {
          switch kind {
          case .value: driverKitValueEvents += 1
          case .report: driverKitReportEvents += 1
          }
        }
        if isUserSpace {
          switch kind {
          case .value: userSpaceValueEvents += 1
          case .report: userSpaceReportEvents += 1
          }
        }
      }
    }
  }

  private func runVirtualDeviceSelfTestInternal(seconds: Int) async -> XPCVirtualDeviceSelfTestPayload
  {
    let driverKitStartCount = Self.readDriverKitInputReportCount()
    let startStats = dextDispatcher.outputStatsSnapshot()

    let counter = SelfTestCounter()
    let counterPtr = Unmanaged.passRetained(counter).toOpaque()

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // IMPORTANT: do not match only "GamePad" usage here.
    //
    // Some installed dext builds (especially during replacement/upgrade or when the app and dext
    // are temporarily out of sync) may not expose the expected usage keys at the IOHIDManager
    // matching layer. Broad matching keeps the self-test reliable; we filter down to OJD devices
    // in the callback using IOUserClass / serial.
    IOHIDManagerSetDeviceMatching(mgr, nil)

    let callback: IOHIDValueCallback = { context, _, sender, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .value)
      }
    }
    IOHIDManagerRegisterInputValueCallback(mgr, callback, counterPtr)

    let reportCallback: IOHIDReportCallback = { context, _, sender, _, _, _, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .report)
      }
    }
    IOHIDManagerRegisterInputReportCallback(mgr, reportCallback, counterPtr)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      print("[XPCService] Self-test IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
    }

    let connectedIdentifiers = await deviceManager.connectedDeviceIdentifiers()
    let syntheticIdentifier =
      connectedIdentifiers.first
      ?? DeviceIdentifier(
        vendorID: 0x4F4A,
        productID: 0x5445,
        serialNumber: "OpenJoystickDriver-SelfTest"
      )
    Task {
      let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
      try? await Task.sleep(for: .milliseconds(250))
      await dextDispatcher.dispatch(events: [.buttonPressed(.a)], from: syntheticIdentifier)
      await userSpace?.dispatch(events: [.buttonPressed(.a)], from: syntheticIdentifier)
      try? await Task.sleep(for: .milliseconds(250))
      await dextDispatcher.dispatch(events: [.buttonReleased(.a)], from: syntheticIdentifier)
      await userSpace?.dispatch(events: [.buttonReleased(.a)], from: syntheticIdentifier)
      try? await Task.sleep(for: .milliseconds(250))
      await dextDispatcher.dispatch(events: [.leftStickChanged(x: 0.75, y: 0)], from: syntheticIdentifier)
      await userSpace?.dispatch(events: [.leftStickChanged(x: 0.75, y: 0)], from: syntheticIdentifier)
      try? await Task.sleep(for: .milliseconds(250))
      await dextDispatcher.dispatch(events: [.leftStickChanged(x: 0, y: 0)], from: syntheticIdentifier)
      await userSpace?.dispatch(events: [.leftStickChanged(x: 0, y: 0)], from: syntheticIdentifier)
    }

    try? await Task.sleep(for: .seconds(Double(seconds)))

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

    let driverKitEndCount = Self.readDriverKitInputReportCount()
    let endStats = dextDispatcher.outputStatsSnapshot()
    let driverKitDelta: Int? = {
      guard let a = driverKitStartCount, let b = driverKitEndCount else { return nil }
      return max(0, b - a)
    }()
    let setReportSuccessDelta = max(0, endStats.successes - startStats.successes)
    let setReportAttemptDelta = max(0, endStats.attempts - startStats.attempts)
    let setReportFailureDelta = max(0, endStats.failures - startStats.failures)
    let connectionAttemptDelta = max(0, endStats.connectionAttempts - startStats.connectionAttempts)
    let connectionSuccessDelta = max(0, endStats.connectionSuccesses - startStats.connectionSuccesses)
    let connectionFailureDelta = max(0, endStats.connectionFailures - startStats.connectionFailures)

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return XPCVirtualDeviceSelfTestPayload(
      seconds: seconds,
      driverKitValueEvents: retained.driverKitValueEvents,
      driverKitReportEvents: retained.driverKitReportEvents,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      driverKitInputReportDelta: driverKitDelta,
      driverKitSetReportSuccessDelta: setReportSuccessDelta,
      driverKitSetReportAttemptDelta: setReportAttemptDelta,
      driverKitSetReportFailureDelta: setReportFailureDelta,
      driverKitSetReportLastErrorHex: endStats.lastErrorHex,
      driverKitConnectionAttemptDelta: connectionAttemptDelta,
      driverKitConnectionSuccessDelta: connectionSuccessDelta,
      driverKitConnectionFailureDelta: connectionFailureDelta,
      driverKitLastConnectionErrorHex: endStats.lastConnectionErrorHex,
      driverKitDiscoverySummary: endStats.lastDiscoverySummary
    )
  }

  /// Best-effort read of the DriverKit virtual device DebugState InputReportCount from IORegistry.
  ///
  /// This avoids relying on IOHID input callbacks (which can be flaky during sysext replacement).
  private static func readDriverKitInputReportCount() -> Int? {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("AppleUserHIDDevice")
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    if kr != KERN_SUCCESS { return nil }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }

      func strProp(_ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? String
      }

      func intProp(_ key: String) -> Int {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? Int ?? 0
      }

      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let ioUserClass = strProp("IOUserClass")
      let product = strProp(kIOHIDProductKey as String)
      let manufacturer = strProp(kIOHIDManufacturerKey as String)
      let vid = intProp(kIOHIDVendorIDKey as String)
      let pid = intProp(kIOHIDProductIDKey as String)

      let looksLikeOJDVirtual =
        (vid == VirtualDeviceProfile.default.vendorID)
        && (pid == VirtualDeviceProfile.default.productID)
        && (product == VirtualDeviceProfile.default.productName)
        && (manufacturer == VirtualDeviceProfile.default.manufacturer)

      let isDriverKit =
        (serial == VirtualDeviceIdentityConstants.driverKitSerialNumber)
        || (ioUserClass == "OpenJoystickVirtualHIDDevice")
        || looksLikeOJDVirtual

      if !isDriverKit { continue }

      guard
        let debug = IORegistryEntryCreateCFProperty(
          service,
          "DebugState" as CFString,
          kCFAllocatorDefault,
          0
        )?.takeRetainedValue() as? [String: Any]
      else { return nil }

      if let n = debug["InputReportCount"] as? NSNumber { return n.intValue }
      if let i = debug["InputReportCount"] as? Int { return i }
      return nil
    }

    return nil
  }
}
