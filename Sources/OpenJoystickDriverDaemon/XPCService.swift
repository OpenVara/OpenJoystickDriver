import Foundation
import OpenJoystickDriverKit

/// Wraps non-Sendable XPC reply closure so it can
/// cross Task boundary. Safe because XPC dispatches
/// reply blocks on its own serial queue.
private struct SendableReply<T>: @unchecked Sendable { let call: (T) -> Void }

/// NSXPCListener server that exposes DeviceManager
/// state to GUI/CLI over Mach IPC.
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
  private let profileStore: ProfileStore
  private let dispatcher: any OutputDispatcher
  private var listener: NSXPCListener?

  public init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    profileStore: ProfileStore,
    dispatcher: any OutputDispatcher
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.profileStore = profileStore
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

  public func listDevices(reply: @escaping ([String]) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let devices = await dm.connectedDeviceDescriptions()
      callback.call(devices)
    }
  }

  public func getStatus(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    let pm = permissionManager
    Task {
      let inputState = await pm.inputMonitoringState
      let devices = await dm.connectedDeviceDescriptions()
      let payload = XPCStatusPayload(
        inputMonitoring: "\(inputState)",
        connectedDevices: devices
      )
      let data = (try? JSONEncoder().encode(payload)) ?? Data()
      callback.call(data)
    }
  }

  public func listProfiles(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      let profiles = await ps.listProfiles()
      let data = (try? JSONEncoder().encode(profiles)) ?? Data()
      callback.call(data)
    }
  }

  public func getProfile(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let profile = await ps.profile(for: identifier)
      let data = (try? JSONEncoder().encode(profile)) ?? Data()
      callback.call(data)
    }
  }

  public func saveProfile(profileData: Data, reply: @escaping (Bool) -> Void) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      guard let profile = try? JSONDecoder().decode(Profile.self, from: profileData) else {
        callback.call(false)
        return
      }
      do {
        try await ps.save(profile)
        callback.call(true)
      } catch {
        print("[XPCService] saveProfile error: \(error)")
        callback.call(false)
      }
    }
  }

  public func resetProfile(vendorID: Int, productID: Int, reply: @escaping (Bool) -> Void) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      do {
        try await ps.reset(for: identifier)
        callback.call(true)
      } catch {
        print("[XPCService] resetProfile error: \(error)")
        callback.call(false)
      }
    }
  }

  public func allProfiles(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let profiles = await ps.allProfiles(for: identifier)
      let data = (try? JSONEncoder().encode(profiles)) ?? Data()
      callback.call(data)
    }
  }

  public func addProfile(
    profileData: Data,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Data?) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      guard var profile = try? JSONDecoder().decode(Profile.self, from: profileData) else {
        callback.call(nil)
        return
      }
      profile.vendorID = UInt16(vendorID)
      profile.productID = UInt16(productID)
      do {
        try await ps.addProfile(profile)
        callback.call(try? JSONEncoder().encode(profile))
      } catch {
        print("[XPCService] addProfile error: \(error)")
        callback.call(nil)
      }
    }
  }

  public func deleteProfile(
    profileId: String,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Bool) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      guard let uuid = UUID(uuidString: profileId) else {
        callback.call(false)
        return
      }
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      do {
        try await ps.deleteProfile(id: uuid, for: identifier)
        callback.call(true)
      } catch {
        print("[XPCService] deleteProfile error: \(error)")
        callback.call(false)
      }
    }
  }

  public func setActiveProfile(
    profileId: String,
    vendorID: Int,
    productID: Int,
    reply: @escaping (Bool) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let ps = profileStore
    Task {
      guard let uuid = UUID(uuidString: profileId) else {
        callback.call(false)
        return
      }
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      do {
        try await ps.setActiveProfile(id: uuid, for: identifier)
        callback.call(true)
      } catch {
        print("[XPCService] setActiveProfile error: \(error)")
        callback.call(false)
      }
    }
  }

  public func getDeviceInputState(vendorID: Int, productID: Int, reply: @escaping (Data?) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let state = await dm.inputState(for: identifier)
      callback.call(try? JSONEncoder().encode(state))
    }
  }

  public func getPacketLog(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let log = await dm.packetLog(for: identifier)
      callback.call((try? JSONEncoder().encode(log)) ?? Data())
    }
  }

  public func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void) {
    dispatcher.suppressOutput = suppress
    reply(true)
  }
}
