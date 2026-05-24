import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerRouteSelectionTests {
  @Test
  func testFrontmostConsumerUsesOwnDedicatedRouteEvenWhenClientsAttachToOtherRoutes() {
    let pcsx2 = "/Applications/PCSX2.app"
    let duckStation = "/Applications/DuckStation.app"

    let activeRoute = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: pcsx2,
      effectiveConsumerBundleRoots: [pcsx2],
      clients: [
        .sample(id: 1, route: UserSpaceVirtualDeviceConstants.sharedRouteToken, bundle: pcsx2),
        .sample(
          id: 2,
          route: UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
            forConsumerBundleRootPath: duckStation
          ),
          bundle: pcsx2
        ),
        .sample(
          id: 3,
          route: UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
            forConsumerBundleRootPath: duckStation
          ),
          bundle: duckStation
        ),
      ]
    )

    #expect(
      activeRoute
        == UserSpaceVirtualDeviceConstants.dedicatedRouteToken(forConsumerBundleRootPath: pcsx2)
    )
  }
}

private extension ForegroundConsumerClientSample {
  static func sample(
    id: UInt64,
    route: String,
    bundle: String,
    opened: Bool = true,
    suspended: Bool = false
  ) -> Self {
    .init(
      clientID: id,
      routeToken: route,
      bundleRootPath: bundle,
      isOpened: opened,
      isSuspended: suspended,
      activitySignature: .init(
        queueHead: 0,
        queueTail: 0,
        queueEntries: 0,
        getReportCount: 0,
        setReportCount: 0,
        setReportErrorCount: 0
      )
    )
  }
}
