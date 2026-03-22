import Foundation
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
  private let dispatcher: any OutputDispatcher
  private var listener: NSXPCListener?

  /// Creates an XPCService backed by the given device manager, permission manager, and output dispatcher.
  public init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: any OutputDispatcher
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
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
      let payload = XPCStatusPayload(inputMonitoring: "\(inputState)", connectedDevices: devices)
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
}
