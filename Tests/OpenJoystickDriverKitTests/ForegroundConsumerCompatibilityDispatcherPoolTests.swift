import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerCompatibilityDispatcherPoolTests {
  @Test
  func testActivatingNeutralDedicatedRouteEmitsNeutralReport() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let bundleRoot = "/Applications/ConsumerA.app"
    let routeToken = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: bundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()

    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    await pool.dispatch(events: [], from: identifier)
    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRoot)
    await pool.setActiveRouteToken(routeToken)

    let dedicated = try #require(dedicatedByRoute.dispatcherIfPresent(for: routeToken))
    #expect(dedicated.recordedDispatches.map(\.events) == [[], []])
    #expect(shared.recordedDispatches.map(\.events) == [[]])
  }

  @Test
  func testRouteHandoffNeutralizesPreviousActiveButtonState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.buttonPressed(.a)], from: identifier)
    await pool.setActiveRouteToken(secondRoute)

    let first = try #require(dedicatedByRoute.dispatcherIfPresent(for: firstRoute))
    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(first.recordedDispatches.map(\.events).contains([.buttonReleased(.a)]))
    #expect(second.recordedDispatches.map(\.events).contains([.buttonPressed(.a)]))
  }

  @Test
  func testRouteHandoffNeutralizesPreviousActiveDpadState() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)
    let firstBundleRoot = "/Applications/ConsumerA.app"
    let secondBundleRoot = "/Applications/ConsumerB.app"
    let firstRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: firstBundleRoot
    )
    let secondRoute = UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: secondBundleRoot
    )

    let shared = RecordingCompatibilityDispatcher(
      routeToken: UserSpaceVirtualDeviceConstants.sharedRouteToken
    )
    let dedicatedByRoute = LockedRouteDispatchers()
    let pool = try ForegroundConsumerCompatibilityDispatcherPool { requestedRouteToken in
      if let requestedRouteToken {
        return dedicatedByRoute.dispatcher(for: requestedRouteToken)
      }
      return shared
    }

    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: firstBundleRoot)
    try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: secondBundleRoot)
    await pool.setActiveRouteToken(firstRoute)
    await pool.dispatch(events: [.dpadChanged(.north)], from: identifier)
    await pool.setActiveRouteToken(secondRoute)

    let first = try #require(dedicatedByRoute.dispatcherIfPresent(for: firstRoute))
    let second = try #require(dedicatedByRoute.dispatcherIfPresent(for: secondRoute))
    #expect(first.recordedDispatches.map(\.events).contains([.dpadChanged(.neutral)]))
    #expect(second.recordedDispatches.map(\.events).contains([.dpadChanged(.north)]))
  }
}

private final class LockedRouteDispatchers: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: RecordingCompatibilityDispatcher] = [:]

  func dispatcher(for routeToken: String) -> RecordingCompatibilityDispatcher {
    lock.withLock {
      if let existing = storage[routeToken] { return existing }
      let dispatcher = RecordingCompatibilityDispatcher(routeToken: routeToken)
      storage[routeToken] = dispatcher
      return dispatcher
    }
  }

  func dispatcherIfPresent(for routeToken: String) -> RecordingCompatibilityDispatcher? {
    lock.withLock { storage[routeToken] }
  }
}

private final class RecordingCompatibilityDispatcher:
  CompatibilityUserSpaceOutputDispatching, @unchecked Sendable
{
  struct RecordedDispatch: Sendable, Equatable {
    let identifier: DeviceIdentifier
    let events: [ControllerEvent]
  }

  let routeToken: String
  var suppressOutput = false
  var status = "on"
  var lastRumbleStatus = "none"
  private(set) var recordedDispatches: [RecordedDispatch] = []

  init(routeToken: String) {
    self.routeToken = routeToken
  }

  func close() {}

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    recordedDispatches.append(.init(identifier: identifier, events: events))
  }
}
