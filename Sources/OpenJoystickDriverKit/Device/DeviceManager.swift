import Foundation
import SwiftUSB

private let usbDetectionPollNanoseconds: UInt64 = 2_000_000_000
private let usbVendorSpecificClass: UInt8 = 0xFF

/// Manages device detection and pipeline lifecycle for all
/// connected controllers.
/// Uses dual detection: SwiftUSB for class 0xFF (GIP) +
/// IOKit HIDManager for class 0x03 (HID).
public actor DeviceManager {
  private struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
  }

  private let parserRegistry: ParserRegistry
  private let dispatcher: any OutputDispatcher
  private let permissionManager: PermissionManager
  private let hidManager: HIDManager
  /// Single libusb context shared across the entire daemon process.
  ///
  /// Creating multiple libusb contexts spins up multiple event threads and can
  /// trigger launchd "inefficient" kills for LaunchAgents.
  private var usbContext: USBContext?
  private var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  private var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  private var detectionTasks: [Task<Void, Never>] = []

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - virtualProfile: Virtual device profile for self-exclusion filtering.
  public init(dispatcher: any OutputDispatcher, virtualProfile: VirtualDeviceProfile = .default) {
    self.dispatcher = dispatcher
    self.parserRegistry = ParserRegistry()
    self.permissionManager = PermissionManager()
    self.hidManager = HIDManager(virtualProfile: virtualProfile)
  }

  /// Start device detection and input processing.
  public func start() async {
    let state = await permissionManager.checkAccess()
    switch state {
    case .unknown, .denied:
      // Request (or re-request) so TCC entry stays current in System Settings.
      // When denied, IOHIDRequestAccess is no-op dialog-wise but keeps entry alive.
      await permissionManager.requestAccess()
      if state == .denied {
        print("[DeviceManager] Input Monitoring denied" + " - running in detect-only mode")
        print(
          "[DeviceManager] Open System Settings" + " > Privacy > Input Monitoring"
            + " to grant access"
        )
      } else {
        print("[DeviceManager] Requesting Input Monitoring" + " permission...")
      }
    case .granted: print("[DeviceManager] Input Monitoring granted")
    }

    ensureUSBContext()

    let usbTask = Task { await self.runUSBDetection() }
    let hidTask = Task { await self.runHIDDetection() }
    detectionTasks = [usbTask, hidTask]

    print("[DeviceManager] Started" + " - dual detection active")
  }

  /// Returns the latest input snapshot for a device matched by vendor and product ID.
  ///
  /// Returns nil if no pipeline is active for the device.
  public func inputState(for identifier: DeviceIdentifier) async -> DeviceInputState? {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }) else { return nil }
    return await pipelines[key]?.inputState()
  }

  /// Returns recent raw USB packets for a device matched by vendor and product ID.
  ///
  /// Returns an empty array if no pipeline is active for the device.
  public func packetLog(for identifier: DeviceIdentifier) async -> [PacketLogEntry] {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }) else { return [] }
    return await pipelines[key]?.getPacketLog() ?? []
  }

  /// Returns structured descriptions for all connected controllers.
  ///
  /// Used by XPCService to report live device list.
  public func connectedDeviceDescriptions() -> [XPCDeviceDescription] {
    pipelines.keys.map { id in
      let info = deviceInfos[id]
      return XPCDeviceDescription(
        name: info?.name ?? "Controller",
        vendorID: id.vendorID,
        productID: id.productID,
        parser: parserRegistry.parserName(for: id),
        connection: info?.connection ?? "USB",
        serialNumber: info?.serialNumber
      )
    }
  }

  /// Stop all detection and pipelines.
  public func stop() async {
    for task in detectionTasks { task.cancel() }
    detectionTasks = []
    for pipeline in pipelines.values { await pipeline.stop() }
    pipelines = [:]
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
  }

  // MARK: - USB detection (class 0xFF)

  private func runUSBDetection() async {
    print("[DeviceManager] USB detection started" + " (class 0xFF)")
    ensureUSBContext()
    guard let context = usbContext else {
      print("[DeviceManager] Failed to create USBContext")
      return
    }

    var knownLocations: Set<String> = []
    var locationToIdentifier: [String: DeviceIdentifier] = [:]

    while !Task.isCancelled {
      let (currentKeys, addedDevices) = await usbDetectCurrentDevices(
        context: context,
        knownLocations: knownLocations
      )

      updateUSBKnownLocations(
        &knownLocations,
        currentKeys: currentKeys,
        addedDevices: addedDevices,
        locationToIdentifier: &locationToIdentifier
      )

      await removeUSBLostDevices(
        knownLocations: &knownLocations,
        currentKeys: currentKeys,
        locationToIdentifier: &locationToIdentifier
      )

      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  private func usbDetectCurrentDevices(context: USBContext, knownLocations: Set<String>) async -> (
    Set<String>, [(device: USBDevice, key: String)]
  ) {
    var currentKeys: Set<String> = []
    var addedDevices: [(device: USBDevice, key: String)] = []
    let stream = context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
    for await device in stream {
      let key = "\(device.bus):\(device.address)"
      currentKeys.insert(key)
      if !knownLocations.contains(key) { addedDevices.append((device, key)) }
    }
    return (currentKeys, addedDevices)
  }

  private func updateUSBKnownLocations(
    _ knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    addedDevices: [(device: USBDevice, key: String)],
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) {
    for (device, key) in addedDevices {
      knownLocations.insert(key)
      if let id = handleUSBDeviceAdded(device) { locationToIdentifier[key] = id }
    }
  }

  private func removeUSBLostDevices(
    knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) async {
    let removedKeys = knownLocations.subtracting(currentKeys)
    for key in removedKeys {
      knownLocations.remove(key)
      if let id = locationToIdentifier.removeValue(forKey: key) {
        let pipeline = pipelines.removeValue(forKey: id)
        deviceInfos.removeValue(forKey: id)
        await pipeline?.stop()
        print("[DeviceManager] USB device removed: \(id)")
      }
    }
  }

  private func ensureUSBContext() {
    if usbContext != nil { return }
    do {
      usbContext = try USBContext()
    } catch {
      usbContext = nil
      print("[DeviceManager] Failed to create USBContext: \(error)")
    }
  }

  @discardableResult private func handleUSBDeviceAdded(_ device: USBDevice) -> DeviceIdentifier? {
    let locationID = UInt32((UInt32(device.bus) << 8) | UInt32(device.address))
    let serial = try? device.getSerialNumber()
    let identifier = DeviceIdentifier(
      vendorID: device.idVendor,
      productID: device.idProduct,
      serialNumber: serial,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else {
      print("[DeviceManager] Pipeline already exists" + " for \(identifier)")
      return nil
    }

    let productName = (try? device.getProduct()) ?? "Controller"
    deviceInfos[identifier] = DeviceInfo(name: productName, connection: "USB", serialNumber: serial)
    print("[DeviceManager] USB device added: \(productName) (\(identifier))")
    let parser = parserRegistry.parser(for: identifier)
    let endpoints = parserRegistry.endpointConfig(for: identifier)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(vendorID: device.idVendor, productID: device.idProduct),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: usbContext,
      endpointConfig: endpoints
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    return identifier
  }

  // MARK: - HID detection (class 0x03)

  private func runHIDDetection() async {
    print("[DeviceManager] HID detection started" + " (class 0x03)")
    for await event in hidManager.deviceEvents() {
      switch event {
      case .connected(let vid, let pid, let serial, let loc, let productName):
        handleHIDDeviceConnected(
          vendorID: vid,
          productID: pid,
          serialNumber: serial,
          locationID: loc,
          productName: productName
        )
      case .disconnected(let vid, let pid, let loc):
        await handleHIDDeviceDisconnected(vendorID: vid, productID: pid, locationID: loc)
      case .inputReport(let loc, let data): await routeHIDInputReport(locationID: loc, data: data)
      }
    }
  }

  private func handleHIDDeviceConnected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?
  ) {
    let identifier = DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serialNumber,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else { return }

    let name = productName ?? "Controller"
    deviceInfos[identifier] = DeviceInfo(name: name, connection: "HID", serialNumber: serialNumber)
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser = parserRegistry.parser(for: identifier)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: locationID),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: nil
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
  }

  private func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
    async
  {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      let pipeline = pipelines.removeValue(forKey: key)
      deviceInfos.removeValue(forKey: key)
      await pipeline?.stop()
      print(
        "[DeviceManager] HID device disconnected:" + " VID=\(vendorID) PID=\(productID)"
          + " loc=\(locationID)"
      )
    }
  }

  private func routeHIDInputReport(locationID: UInt32, data: Data) async {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      await pipelines[key]?.feedHIDData(data)
    }
  }
}
