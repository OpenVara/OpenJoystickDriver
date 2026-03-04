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
  }

  private let parserRegistry: ParserRegistry
  private let dispatcher: any OutputDispatcher
  private let permissionManager: PermissionManager
  private let hidManager: HIDManager
  private var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  private var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  private var detectionTasks: [Task<Void, Never>] = []

  public init(dispatcher: any OutputDispatcher) {
    self.dispatcher = dispatcher
    self.parserRegistry = ParserRegistry()
    self.permissionManager = PermissionManager()
    self.hidManager = HIDManager()
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

    let usbTask = Task { await self.runUSBDetection() }
    let hidTask = Task { await self.runHIDDetection() }
    detectionTasks = [usbTask, hidTask]

    print("[DeviceManager] Started" + " - dual detection active")
  }

  /// Returns description strings for all connected controllers.
  /// Format: "NAME (VID:D PID:D PARSER [CONNECTION])"
  /// Used by XPCService to report live device list.
  public func connectedDeviceDescriptions() -> [String] {
    pipelines.keys.map { id in
      let info = deviceInfos[id]
      let name = info?.name ?? "Controller"
      let connection = info?.connection ?? "USB"
      let parser = parserRegistry.parserName(for: id)
      return "\(name) (VID:\(id.vendorID) PID:\(id.productID) \(parser) [\(connection)])"
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
    guard let context = try? USBContext() else {
      print("[DeviceManager] Failed to create USBContext")
      return
    }

    var knownLocations: Set<String> = []

    while !Task.isCancelled {
      var currentKeys: Set<String> = []
      let stream = context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
      for await device in stream {
        let key = "\(device.bus):\(device.address)"
        currentKeys.insert(key)
        if !knownLocations.contains(key) {
          knownLocations.insert(key)
          handleUSBDeviceAdded(device)
        }
      }

      let removedKeys = knownLocations.subtracting(currentKeys)
      for key in removedKeys {
        knownLocations.remove(key)
        print("[DeviceManager] USB device removed: \(key)")
      }

      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  private func handleUSBDeviceAdded(_ device: USBDevice) {
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
      return
    }

    let productName = (try? device.getProduct()) ?? "Controller"
    deviceInfos[identifier] = DeviceInfo(name: productName, connection: "USB")
    print("[DeviceManager] USB device added: \(productName) (\(identifier))")
    let parser = parserRegistry.parser(for: identifier)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(vendorID: device.idVendor, productID: device.idProduct),
      parser: parser,
      dispatcher: dispatcher
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
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
    deviceInfos[identifier] = DeviceInfo(name: name, connection: "HID")
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser = parserRegistry.parser(for: identifier)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: locationID),
      parser: parser,
      dispatcher: dispatcher
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
