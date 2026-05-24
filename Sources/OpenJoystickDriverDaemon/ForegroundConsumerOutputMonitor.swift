import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// Gates controller output unless the frontmost app is one of the current
/// OpenJoystickDriver virtual-device consumers.
final class ForegroundConsumerOutputMonitor: @unchecked Sendable {
  private let deviceManager: DeviceManager
  private let compatibilityRouteHandler:
    @Sendable (String?, Set<String>, Set<String>, String?) async -> Void
  private let pollIntervalNanoseconds: UInt64
  private let burstPollIntervalNanoseconds: UInt64
  private let burstPollDurationNanoseconds: UInt64
  private let stateLock = NSLock()
  private var periodicTask: Task<Void, Never>?
  private var burstTask: Task<Void, Never>?
  private var burstPollingDeadlineNanoseconds: UInt64 = 0
  private var activationObserver: NSObjectProtocol?
  private var activityTracker = ForegroundConsumerActivityTracker()
  private var lastAppliedAllowOutput: Bool?
  private var lastAppliedFrontmostBundleRoot: String?
  private var lastAppliedConsumerBundleRoots: Set<String> = []
  private var lastAppliedObservedBundleRoots: Set<String> = []
  private var lastAppliedActiveRouteToken: String?

  init(
    deviceManager: DeviceManager,
    compatibilityRouteHandler:
      @escaping @Sendable (String?, Set<String>, Set<String>, String?) async -> Void = {
        _, _, _, _ in
      },
    pollIntervalNanoseconds: UInt64 = 1_000_000_000,
    burstPollIntervalNanoseconds: UInt64 = 100_000_000,
    burstPollDurationNanoseconds: UInt64 = 3_000_000_000
  ) {
    self.deviceManager = deviceManager
    self.compatibilityRouteHandler = compatibilityRouteHandler
    self.pollIntervalNanoseconds = pollIntervalNanoseconds
    self.burstPollIntervalNanoseconds = burstPollIntervalNanoseconds
    self.burstPollDurationNanoseconds = burstPollDurationNanoseconds
  }

  func start() {
    stateLock.withLock {
      guard periodicTask == nil else { return }
      periodicTask = Task { [weak self] in
        guard let self else { return }
        await self.evaluateAndApply()
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
          await self.evaluateAndApply()
        }
      }
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      let center = NSWorkspace.shared.notificationCenter
      activationObserver = center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.scheduleBurstPolling()
        Task { await self?.evaluateAndApply() }
      }
    }
  }

  private func scheduleBurstPolling() {
    stateLock.withLock {
      burstPollingDeadlineNanoseconds = max(
        burstPollingDeadlineNanoseconds,
        DispatchTime.now().uptimeNanoseconds &+ burstPollDurationNanoseconds
      )
      guard burstTask == nil else { return }
      burstTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
          await self.evaluateAndApply()

          let shouldContinue = self.stateLock.withLock { () -> Bool in
            DispatchTime.now().uptimeNanoseconds < burstPollingDeadlineNanoseconds
          }
          guard shouldContinue else {
            self.stateLock.withLock {
              burstTask = nil
              burstPollingDeadlineNanoseconds = 0
            }
            return
          }

          try? await Task.sleep(nanoseconds: self.burstPollIntervalNanoseconds)
        }

        self.stateLock.withLock {
          burstTask = nil
          burstPollingDeadlineNanoseconds = 0
        }
      }
    }
  }

  private func evaluateAndApply() async {
    let frontmostBundleRoot = await MainActor.run { Self.frontmostBundleRootPath() }
    let now = DispatchTime.now().uptimeNanoseconds
    let consumerClients = Self.consumerClientSamples()
    let observedBundleRoots = Set(
      consumerClients
        .filter { $0.isOpened && !$0.isSuspended }
        .map(\.bundleRootPath)
    )
    let consumerBundleRoots = stateLock.withLock {
      activityTracker.consumerBundleRootPaths(
        frontmostBundleRootPath: frontmostBundleRoot,
        clients: consumerClients,
        now: now
      )
    }
    let activeRouteToken = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: frontmostBundleRoot,
      effectiveConsumerBundleRoots: consumerBundleRoots,
      clients: consumerClients
    )
    let policyAllowsOutput = ForegroundConsumerAccessPolicy.allowsOutput(
      frontmostBundleRootPath: frontmostBundleRoot,
      consumerBundleRootPaths: consumerBundleRoots
    )
    let allowOutput = policyAllowsOutput

    let needsApply = stateLock.withLock { () -> Bool in
      let changed =
        lastAppliedAllowOutput != allowOutput
        || lastAppliedFrontmostBundleRoot != frontmostBundleRoot
        || lastAppliedConsumerBundleRoots != consumerBundleRoots
        || lastAppliedObservedBundleRoots != observedBundleRoots
        || lastAppliedActiveRouteToken != activeRouteToken
      guard changed else { return false }
      lastAppliedAllowOutput = allowOutput
      lastAppliedFrontmostBundleRoot = frontmostBundleRoot
      lastAppliedConsumerBundleRoots = consumerBundleRoots
      lastAppliedObservedBundleRoots = observedBundleRoots
      lastAppliedActiveRouteToken = activeRouteToken
      return true
    }

    guard needsApply else { return }

    await compatibilityRouteHandler(
      frontmostBundleRoot,
      consumerBundleRoots,
      observedBundleRoots,
      activeRouteToken
    )

    if allowOutput {
      if consumerBundleRoots.isEmpty {
        print(
          "[ForegroundConsumerOutputMonitor] Output active "
            + "(no consumer apps holding OJD virtual device)"
        )
      } else if let frontmostBundleRoot {
        let observedLabel = Self.bundleLabelList(observedBundleRoots)
        let effectiveLabel = Self.bundleLabelList(consumerBundleRoots)
        let routeLabel = activeRouteToken ?? "none"
        print(
          "[ForegroundConsumerOutputMonitor] Output active for frontmost consumer: "
            + "\(URL(fileURLWithPath: frontmostBundleRoot).lastPathComponent)"
            + " route=\(routeLabel)"
            + (observedBundleRoots == consumerBundleRoots
              ? ""
              : " effective=[\(effectiveLabel)] observed=[\(observedLabel)]")
        )
      } else {
        print("[ForegroundConsumerOutputMonitor] Output active")
      }
    } else {
      let frontmostLabel =
        frontmostBundleRoot.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "none"
      let consumersLabel = Self.bundleLabelList(consumerBundleRoots)
      let observedLabel = Self.bundleLabelList(observedBundleRoots)
      let routeLabel = activeRouteToken ?? "none"
      print(
        "[ForegroundConsumerOutputMonitor] Output gated; frontmost=\(frontmostLabel) "
          + "consumers=[\(consumersLabel)] route=\(routeLabel)"
          + (observedBundleRoots == consumerBundleRoots ? "" : " observed=[\(observedLabel)]")
      )
    }

    await deviceManager.setExternalOutputAllowed(allowOutput)
  }

  @MainActor
  private static func frontmostBundleRootPath() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return bundleRootPath(for: app)
  }

  private static func consumerClientSamples() -> [ForegroundConsumerClientSample] {
    var samples: [ForegroundConsumerClientSample] = []
    for service in virtualDeviceServices() {
      defer { IOObjectRelease(service) }
      samples.append(contentsOf: consumerClientSamples(under: service))
    }
    return samples
  }

  private static func virtualDeviceServices() -> [io_service_t] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else { return [] }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let rawDevices = IOHIDManagerCopyDevices(manager) else { return [] }
    let devices = rawDevices as? Set<IOHIDDevice> ?? []
    var services: [io_service_t] = []

    for device in devices {
      let service = IOHIDDeviceGetService(device)
      guard service != 0 else { continue }
      guard isOJDVirtualDevice(service: service, device: device) else { continue }
      IOObjectRetain(service)
      services.append(service)
    }

    return services
  }

  private static func isOJDVirtualDevice(service: io_service_t, device: IOHIDDevice) -> Bool {
    func stringProperty(_ key: String) -> String? {
      if let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String {
        return value
      }
      return IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    func intProperty(_ key: String) -> Int {
      if let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? Int {
        return value
      }
      if let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? Int64 {
        return Int(value)
      }
      if let value = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? Int {
        return value
      }
      return IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
    }

    let serial = stringProperty(kIOHIDSerialNumberKey as String) ?? stringProperty("SerialNumber")
    if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { return true }
    if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { return true }

    let ioUserClass = stringProperty("IOUserClass")
    if ioUserClass == "OpenJoystickVirtualHIDDevice" { return true }

    let rawLocation = UInt32(truncatingIfNeeded: intProperty(kIOHIDLocationIDKey as String))
    if rawLocation == VirtualDeviceIdentityConstants.driverKitLocationID { return true }
    if (rawLocation & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace {
      return true
    }

    return false
  }

  private static func consumerClientSamples(
    under service: io_service_t
  ) -> [ForegroundConsumerClientSample] {
    let routeToken = userSpaceRouteToken(for: service)
    var iterator: io_iterator_t = 0
    let kr = IORegistryEntryCreateIterator(
      service,
      kIOServicePlane,
      IOOptionBits(kIORegistryIterateRecursively),
      &iterator
    )
    guard kr == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var samples: [ForegroundConsumerClientSample] = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      guard let sample = clientSample(entry: entry, routeToken: routeToken) else { continue }
      samples.append(sample)
    }
    return samples
  }

  private static func clientSample(
    entry: io_registry_entry_t,
    routeToken: String
  ) -> ForegroundConsumerClientSample? {
    guard
      let ioUserClass = IOObjectCopyClass(entry)?.takeRetainedValue() as String?,
      ioUserClass == "IOHIDLibUserClient"
    else {
      return nil
    }

    let creatorValue = IORegistryEntryCreateCFProperty(
      entry,
      "IOUserClientCreator" as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue()
    guard let pid = ForegroundConsumerClientOwner.pid(from: creatorValue) else { return nil }
    guard let bundleRootPath = bundleRootPath(for: pid_t(pid)) else { return nil }
    guard !isIgnoredConsumerBundleRoot(bundleRootPath) else { return nil }

    var clientID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(entry, &clientID) == KERN_SUCCESS else { return nil }

    let debugState = dictionaryProperty("DebugState", entry: entry)
    let queue = eventQueueMap(from: debugState["EventQueueMap"])

    return ForegroundConsumerClientSample(
      clientID: clientID,
      routeToken: routeToken,
      bundleRootPath: bundleRootPath,
      isOpened: boolProperty("ClientOpened", dictionary: debugState) ?? true,
      isSuspended: boolProperty("ClientSuspended", dictionary: debugState) ?? false,
      activitySignature: .init(
        queueHead: intValue(queue["head"]),
        queueTail: intValue(queue["tail"]),
        queueEntries: intValue(queue["numEntries"]),
        getReportCount: boolProperty("ClientOpened", dictionary: debugState) == nil
          ? 0
          : (intValue(debugState["GetReportCnt"]) ?? 0),
        setReportCount: intValue(debugState["SetReportCnt"]) ?? 0,
        setReportErrorCount: intValue(debugState["SetReportErrCnt"]) ?? 0
      )
    )
  }

  private static func intProperty(_ key: String, entry: io_registry_entry_t) -> Int? {
    if let value = IORegistryEntryCreateCFProperty(
      entry,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Int {
      return value
    }
    if let value = IORegistryEntryCreateCFProperty(
      entry,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Int64 {
      return Int(value)
    }
    return IORegistryEntryCreateCFProperty(
      entry,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Int
  }

  private static func userSpaceRouteToken(for service: io_service_t) -> String {
    let serial =
      IORegistryEntryCreateCFProperty(
        service,
        kIOHIDSerialNumberKey as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String
      ?? IORegistryEntryCreateCFProperty(
        service,
        "SerialNumber" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String
    return UserSpaceVirtualDeviceConstants.routeToken(from: serial)
      ?? UserSpaceVirtualDeviceConstants.sharedRouteToken
  }

  private static func dictionaryProperty(
    _ key: String,
    entry: io_registry_entry_t
  ) -> [String: Any] {
    IORegistryEntryCreateCFProperty(
      entry,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? [String: Any] ?? [:]
  }

  private static func eventQueueMap(from value: Any?) -> [String: Any] {
    if let dict = value as? [String: Any] { return dict }
    if let array = value as? [[String: Any]], let first = array.first { return first }
    if let array = value as? [Any], let first = array.first as? [String: Any] { return first }
    return [:]
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? Int64 { return Int(number) }
    return value as? Int
  }

  private static func boolProperty(_ key: String, dictionary: [String: Any]) -> Bool? {
    guard let value = dictionary[key] else { return nil }
    if let number = value as? Bool { return number }
    if let number = value as? Int { return number != 0 }
    if let number = value as? Int64 { return number != 0 }
    return value as? Bool
  }

  private static func bundleLabelList(_ bundleRoots: Set<String>) -> String {
    bundleRoots
      .map { URL(fileURLWithPath: $0).lastPathComponent }
      .sorted()
      .joined(separator: ", ")
  }

  private static func bundleRootPath(for pid: pid_t) -> String? {
    let pidPathBufferSize = Int(MAXPATHLEN * 4)
    var buffer = [CChar](repeating: 0, count: pidPathBufferSize)
    let copied = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard copied > 0 else { return nil }

    let pathBytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
    guard let path = String(bytes: pathBytes, encoding: .utf8) else { return nil }
    var url = URL(fileURLWithPath: path)
    while url.path != "/" && !url.path.isEmpty {
      if url.pathExtension == "app" { return url.path }
      url.deleteLastPathComponent()
    }
    return nil
  }

  private static func bundleRootPath(for application: NSRunningApplication?) -> String? {
    guard let application else { return nil }
    if let bundleURL = application.bundleURL, bundleURL.pathExtension == "app" {
      return bundleURL.path
    }
    return bundleRootPath(for: application.processIdentifier)
  }

  private static func isIgnoredConsumerBundleRoot(_ bundleRoot: String) -> Bool {
    if let bundleIdentifier = Bundle(path: bundleRoot)?.bundleIdentifier,
      bundleIdentifier.hasPrefix("com.openjoystickdriver")
    {
      return true
    }
    let name = URL(fileURLWithPath: bundleRoot).lastPathComponent
    return name == "OpenJoystickDriver.app" || name == "OpenJoystickDriverDaemon.app"
  }

}
