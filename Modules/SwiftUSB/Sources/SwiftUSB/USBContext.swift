import CLibUSB
import Dispatch
import Foundation

/// Sendable wrapper for C opaque pointer.
/// Safe because libusb context pointer outlives all closures that use it -
/// enforced by deinit semaphore in USBContext.
private struct SendablePointer: @unchecked Sendable { let value: OpaquePointer }

/// Thread-safe boolean flag for controlling event loop.
private final class AtomicFlag: @unchecked Sendable {
  private var _value: Bool
  private let lock = NSLock()

  init(_ value: Bool) { _value = value }

  var value: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }
}

/// Entry point for finding and opening USB devices via libusb.
///
/// Create one context per process. A background thread runs the libusb
/// event loop for the lifetime of the context and is stopped cleanly on dealloc.
public final class USBContext: @unchecked Sendable {
  private let context: OpaquePointer
  private let eventQueue: DispatchQueue
  private let eventLoopDone: DispatchSemaphore
  private let running = AtomicFlag(true)

  private static let TIMEOUT = -7

  /// Creates a libusb context and starts the internal event loop.
  /// Throws ``USBError`` when libusb cannot be initialized.
  public init() throws {
    var ctx: OpaquePointer?
    let result = libusb_init(&ctx)
    if result < 0 { throw USBError(code: result) }
    guard let context = ctx else { throw USBError(message: "Failed to initialize USB context") }
    self.context = context
    self.eventQueue = DispatchQueue(label: "swiftusb.events", qos: .utility)
    self.eventLoopDone = DispatchSemaphore(value: 0)
    startEventHandling()
  }

  deinit {
    running.value = false
    // libusb_handle_events_timeout call returns (max 100ms)
    _ = eventLoopDone.wait(timeout: .now() + 1.0)
    libusb_exit(context)
  }

  private func startEventHandling() {
    let done = eventLoopDone
    let ctx = SendablePointer(value: context)
    let runFlag = running
    eventQueue.async { [ctx, runFlag, done] in
      defer { done.signal() }
      while runFlag.value {
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        let result = libusb_handle_events_timeout(ctx.value, &timeout)
        if result == Self.TIMEOUT { continue }
        guard result >= 0 else {
          print("[SwiftUSB] Event handling error: \(String(cString: libusb_error_name(result)))")
          continue
        }
      }
    }
  }

  /// Returns an async stream of USB devices that match the given filters.
  ///
  /// All filters are optional — omit them to match every connected device.
  /// Set `findAll` to false to stop the stream after the first match.
  public func findDevices(
    vendorId: UInt16? = nil,
    productId: UInt16? = nil,
    deviceClass: UInt8? = nil,
    findAll: Bool = true
  ) -> AsyncStream<USBDevice> {
    AsyncStream { [weak self] continuation in
      guard let self else {
        continuation.finish()
        return
      }

      guard let prepared = self.prepareDeviceList() else {
        continuation.finish()
        return
      }

      defer {
        libusb_free_device_list(prepared.pointer.pointee, 1)
        prepared.pointer.deallocate()
      }

      guard let deviceList = prepared.pointer.pointee else {
        continuation.finish()
        return
      }

      _ = self.processDeviceList(
        deviceList: deviceList,
        count: prepared.count,
        vendorId: vendorId,
        productId: productId,
        deviceClass: deviceClass,
        findAll: findAll,
        continuation: continuation
      )

      continuation.finish()
    }
  }

  /// Returns the first connected device with the given vendor and product ID,
  /// or nil when no matching device is found.
  public func findDevice(vendorId: UInt16, productId: UInt16) async -> USBDevice? {
    var found: USBDevice?
    for await device in findDevices(vendorId: vendorId, productId: productId, findAll: false) {
      found = device
      break
    }
    return found
  }

  private func prepareDeviceList() -> (
    pointer: UnsafeMutablePointer<UnsafeMutablePointer<OpaquePointer?>?>, count: Int
  )? {
    let deviceListPtr = UnsafeMutablePointer<UnsafeMutablePointer<OpaquePointer?>?>.allocate(
      capacity: 1
    )
    let count = libusb_get_device_list(self.context, deviceListPtr)

    guard count >= 0 else {
      deviceListPtr.deallocate()
      return nil
    }

    guard count > 0 else {
      deviceListPtr.deallocate()
      return nil
    }

    return (pointer: deviceListPtr, count: Int(count))
  }

  private func processDeviceList(
    deviceList: UnsafeMutablePointer<OpaquePointer?>,
    count: Int,
    vendorId: UInt16?,
    productId: UInt16?,
    deviceClass: UInt8?,
    findAll: Bool,
    continuation: AsyncStream<USBDevice>.Continuation
  ) -> Int {
    var deviceCount = 0

    for i in 0..<count {
      guard let device = deviceList[i] else { continue }

      guard let descriptor = self.createDescriptor(for: device, at: i) else { continue }

      if !deviceMatchesFilters(
        descriptor: descriptor.pointee,
        vendorId: vendorId,
        productId: productId,
        deviceClass: deviceClass
      ) {
        descriptor.deallocate()
        continue
      }

      continuation.yield(USBDevice(device: device, descriptor: descriptor.pointee))
      deviceCount += 1

      if !findAll { break }
    }

    return deviceCount
  }

  private func createDescriptor(for device: OpaquePointer, at index: Int) -> UnsafeMutablePointer<
    libusb_device_descriptor
  >? {
    let descriptor = UnsafeMutablePointer<libusb_device_descriptor>.allocate(capacity: 1)
    let result = libusb_get_device_descriptor(device, descriptor)

    guard result == 0 else {
      descriptor.deallocate()
      return nil
    }

    return descriptor
  }

  private func deviceMatchesFilters(
    descriptor: libusb_device_descriptor,
    vendorId: UInt16?,
    productId: UInt16?,
    deviceClass: UInt8?
  ) -> Bool {
    if let filterVID = vendorId, descriptor.idVendor != filterVID { return false }
    if let filterPID = productId, descriptor.idProduct != filterPID { return false }
    if let filterClass = deviceClass, descriptor.bDeviceClass != filterClass { return false }
    return true
  }
}
