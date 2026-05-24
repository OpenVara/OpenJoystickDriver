import Foundation

/// Compatibility user-space output that keeps one bootstrap/shared device plus
/// lazily-created dedicated devices for focused consumer apps.
///
/// Real controller state is routed only to the currently active route token.
/// Non-active routes are neutralized on handoff.
public final class ForegroundConsumerCompatibilityDispatcherPool:
  CompatibilityUserSpaceOutputDispatching, @unchecked Sendable
{
  public typealias ChildFactory =
    @Sendable (String?) throws -> any CompatibilityUserSpaceOutputDispatching

  private let lock = NSLock()
  private let childFactory: ChildFactory
  private let sharedDispatcher: any CompatibilityUserSpaceOutputDispatching
  private var dedicatedDispatchers: [String: any CompatibilityUserSpaceOutputDispatching] = [:]
  private var activeRouteToken: String?
  private var knownIdentifiers: Set<DeviceIdentifier> = []
  private var currentStateByIdentifier: [DeviceIdentifier: DeviceInputState] = [:]
  private var _suppressOutput = false

  public init(childFactory: @escaping ChildFactory) throws {
    self.childFactory = childFactory
    self.sharedDispatcher = try childFactory(nil)
  }

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      let children = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
        _suppressOutput = newValue
        return [sharedDispatcher] + Array(dedicatedDispatchers.values)
      }
      for child in children {
        child.suppressOutput = newValue
      }
    }
  }

  public var status: String {
    lock.withLock {
      let activeLabel = activeRouteToken ?? "none"
      let routeCount = 1 + dedicatedDispatchers.count
      let childStatuses = [sharedDispatcher.status] + dedicatedDispatchers.values.map(\.status)
      if let errorStatus = childStatuses.first(where: { $0.hasPrefix("error:") }) {
        return errorStatus
      }
      if childStatuses.allSatisfy({ $0 == "off" }) {
        return "off"
      }
      return "on (routes=\(routeCount), active=\(activeLabel))"
    }
  }

  public var lastRumbleStatus: String {
    lock.withLock {
      if let active = dispatcher(for: activeRouteToken),
        active.lastRumbleStatus != "none"
      {
        return active.lastRumbleStatus
      }
      let all = [sharedDispatcher] + Array(dedicatedDispatchers.values)
      return all.first { $0.lastRumbleStatus != "none" }?.lastRumbleStatus ?? "none"
    }
  }

  public func close() {
    let children = lock.withLock { () -> [any CompatibilityUserSpaceOutputDispatching] in
      let all = [sharedDispatcher] + Array(dedicatedDispatchers.values)
      dedicatedDispatchers.removeAll()
      activeRouteToken = nil
      knownIdentifiers.removeAll()
      currentStateByIdentifier.removeAll()
      return all
    }

    for child in children {
      child.close()
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    let activeDispatcher = lock.withLock { () -> (any CompatibilityUserSpaceOutputDispatching)? in
      knownIdentifiers.insert(identifier)
      var state =
        currentStateByIdentifier[identifier]
        ?? DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.apply(events: events)
      currentStateByIdentifier[identifier] = state
      return dispatcher(for: activeRouteToken)
    }

    if events.isEmpty {
      await sharedDispatcher.dispatch(events: [], from: identifier)
      return
    }

    guard let activeDispatcher else { return }
    await activeDispatcher.dispatch(events: events, from: identifier)
  }

  public func ensureDedicatedRoute(forConsumerBundleRootPath bundleRootPath: String) async throws {
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRootPath
    )

    let created: (any CompatibilityUserSpaceOutputDispatching)?
    let identifiers: [DeviceIdentifier]

    if let existing = lock.withLock { dedicatedDispatchers[routeToken] } {
      existing.suppressOutput = suppressOutput
      return
    }

    let child = try childFactory(routeToken)
    child.suppressOutput = suppressOutput

    created = lock.withLock { () -> (any CompatibilityUserSpaceOutputDispatching)? in
      if let existing = dedicatedDispatchers[routeToken] {
        return existing
      }
      dedicatedDispatchers[routeToken] = child
      return child
    }
    identifiers = lock.withLock { Array(knownIdentifiers) }

    if let created {
      for identifier in identifiers {
        await created.dispatch(events: [], from: identifier)
      }
      print(
        "[ForegroundConsumerCompatibilityDispatcherPool] Created dedicated Compatibility route "
          + "\(routeToken) for \(URL(fileURLWithPath: bundleRootPath).lastPathComponent)"
      )
    }
  }

  public func setActiveRouteToken(_ newActiveRouteToken: String?) async {
    let previousToken: String?
    let states: [DeviceIdentifier: DeviceInputState]

    (previousToken, states) = lock.withLock {
      let old = activeRouteToken
      guard old != newActiveRouteToken else { return (old, [:]) }
      activeRouteToken = newActiveRouteToken
      return (old, currentStateByIdentifier)
    }

    guard previousToken != newActiveRouteToken else { return }

    if let previousDispatcher = dispatcher(for: previousToken) {
      for (identifier, state) in states {
        let neutralizingEvents = state.neutralizingEvents()
        if !neutralizingEvents.isEmpty {
          await previousDispatcher.dispatch(events: neutralizingEvents, from: identifier)
        }
      }
    }

    if let nextDispatcher = dispatcher(for: newActiveRouteToken) {
      for (identifier, state) in states {
        let currentEvents = state.currentEvents()
        await nextDispatcher.dispatch(events: currentEvents, from: identifier)
      }
    }
  }

  private func dispatcher(
    for routeToken: String?
  ) -> (any CompatibilityUserSpaceOutputDispatching)? {
    if routeToken == nil { return nil }
    if routeToken == UserSpaceVirtualDeviceConstants.sharedRouteToken {
      return sharedDispatcher
    }
    return dedicatedDispatchers[routeToken ?? ""]
  }
}
