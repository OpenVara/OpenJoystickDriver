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
  private var userSpaceDispatcher: UserSpaceOutputDispatcher?
  private var userSpaceEnabled: Bool
  private var userSpaceStatus: String = "off"
  private var virtualDeviceMode: VirtualDeviceMode
  /// Actual routing mode currently applied.
  private var effectiveOutputMode: CompositeOutputDispatcher.Mode
  private var listener: NSXPCListener?
  private static let userSpaceEnabledDefaultsKey = "UserSpaceVirtualDeviceEnabled"
  private static let outputModeDefaultsKey = "OutputMode"  // legacy
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
    let savedVirtual = UserDefaults.standard.string(forKey: Self.virtualDeviceModeDefaultsKey)
    if let raw = savedVirtual, let mode = VirtualDeviceMode(rawValue: raw) {
      self.virtualDeviceMode = mode
    } else {
      // Migration from legacy keys (OutputMode + userSpaceEnabled).
      let savedMode = UserDefaults.standard.string(forKey: Self.outputModeDefaultsKey)
      let parsed = CompositeOutputDispatcher.Mode(rawValue: savedMode ?? "")
      if parsed == .both {
        self.virtualDeviceMode = .both
      } else if userSpaceEnabled {
        self.virtualDeviceMode = .compatUserSpace
      } else {
        self.virtualDeviceMode = .auto
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
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
    case .driverKit:
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
    case .compatUserSpace:
      dextDispatcher.setEnabled(false)
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        effectiveOutputMode = .secondaryOnly
        dispatcher.setMode(.secondaryOnly)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.secondaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
      } else {
        // Fail closed: stay DriverKit-only.
        virtualDeviceMode = .driverKit
        UserDefaults.standard.set(
          VirtualDeviceMode.driverKit.rawValue,
          forKey: Self.virtualDeviceModeDefaultsKey
        )
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
      }
    case .both:
      dextDispatcher.setEnabled(true)
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        effectiveOutputMode = .both
        dispatcher.setMode(.both)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.both.rawValue, forKey: Self.outputModeDefaultsKey)
      } else {
        virtualDeviceMode = .driverKit
        UserDefaults.standard.set(
          VirtualDeviceMode.driverKit.rawValue,
          forKey: Self.virtualDeviceModeDefaultsKey
        )
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(CompositeOutputDispatcher.Mode.primaryOnly.rawValue, forKey: Self.outputModeDefaultsKey)
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
        return "\(d.name) (VID:\(d.vendorID)" + " PID:\(d.productID) \(d.parser)"
          + " [\(d.connection)] SN:\(sn))"
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
      let userStatus = userSpaceStatus
      let payload = XPCStatusPayload(
        inputMonitoring: "\(inputState)",
        connectedDevices: devices,
        userSpaceVirtualDeviceEnabled: userEnabled,
        userSpaceVirtualDeviceStatus: userStatus,
        virtualDeviceMode: virtualDeviceMode.rawValue,
        effectiveOutputMode: effectiveOutputMode.rawValue
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
    reply(userSpaceStatus)
  }

  public func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      let enabled = userSpaceEnabled
      let status = userSpaceStatus
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
    // Legacy API: reflect current virtual mode.
    switch virtualDeviceMode {
    case .auto: reply(effectiveOutputMode.rawValue)
    case .driverKit: reply(CompositeOutputDispatcher.Mode.primaryOnly.rawValue)
    case .compatUserSpace: reply(CompositeOutputDispatcher.Mode.secondaryOnly.rawValue)
    case .both: reply(CompositeOutputDispatcher.Mode.both.rawValue)
    }
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

  // MARK: - Private

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
        let ud = try UserSpaceOutputDispatcher()
        userSpaceDispatcher = ud
        dispatcher.setSecondary(ud)
        userSpaceEnabled = true
        userSpaceStatus = ud.status
        UserDefaults.standard.set(true, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[XPCService] Enabled user-space virtual gamepad")
        return true
      } catch {
        dispatcher.setSecondary(nil)
        userSpaceDispatcher = nil
        userSpaceEnabled = false
        userSpaceStatus = "error: \(error)"
        UserDefaults.standard.set(false, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[XPCService] Failed to enable user-space virtual gamepad: \(error)")
        return false
      }
    } else {
      dispatcher.setSecondary(nil)
      userSpaceDispatcher?.close()
      userSpaceDispatcher = nil
      userSpaceEnabled = false
      userSpaceStatus = "off"
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
      let ioUserClass = IOHIDDeviceGetProperty(device, "IOUserClass" as CFString) as? String
      let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
      let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0

      let isDriverKit =
        (ioUserClass == "OpenJoystickVirtualHIDDevice")
        || (serial == VirtualDeviceIdentityConstants.driverKitSerialNumber)
        || (location == Int(VirtualDeviceIdentityConstants.driverKitLocationID))

      let isUserSpace =
        (ioUserClass == "IOHIDUserDevice")
        || (serial == UserSpaceVirtualDeviceConstants.serialNumber)
        || (location == Int(VirtualDeviceIdentityConstants.userSpaceLocationID))

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

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return XPCVirtualDeviceSelfTestPayload(
      seconds: seconds,
      driverKitValueEvents: retained.driverKitValueEvents,
      driverKitReportEvents: retained.driverKitReportEvents,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      driverKitInputReportDelta: driverKitDelta,
      driverKitSetReportSuccessDelta: setReportSuccessDelta
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

      let ioUserClass = strProp("IOUserClass")
      if ioUserClass != "OpenJoystickVirtualHIDDevice" { continue }

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
