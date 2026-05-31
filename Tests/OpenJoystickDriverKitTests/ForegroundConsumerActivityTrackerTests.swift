import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerActivityTrackerTests {
  @Test
  func testSingleOpenBundleRemainsConsumerWithoutRecentActivity() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(
          id: 1,
          bundle: "/Applications/ConsumerA.app",
          queueHead: 0,
          queueTail: 0,
        ),
      ],
      now: 10
    )

    #expect(roots == ["/Applications/ConsumerA.app"])
  }

  @Test

  func testMultipleOpenBundlesPreferFrontmostBundleBeforeAnyRecentActivity() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerB.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 0, queueTail: 0),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 10
    )

    #expect(roots == ["/Applications/ConsumerB.app"])
  }

  @Test

  func testMultipleOpenBundlesGateWhenFrontmostAppIsNotConsumerAndNoRecentActivityExists() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/System/Library/CoreServices/Finder.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 0, queueTail: 0),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 10
    )

    #expect(roots == ["/Applications/ConsumerA.app", "/Applications/ConsumerB.app"])
  }

  @Test

  func testRecentlyChangingBackgroundClientDoesNotOverrideFrontmostConsumer() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    _ = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 0, queueTail: 0),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 10
    )

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 0, queueTail: 0),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 4, queueTail: 4),
      ],
      now: 20
    )

    #expect(roots == ["/Applications/ConsumerA.app"])
  }

  @Test

  func testFirstObservedNonZeroBaselinesDoNotOverrideFrontmostBundle() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 480, queueTail: 480),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 480, queueTail: 480),
      ],
      now: 10
    )

    #expect(roots == ["/Applications/ConsumerA.app"])
  }

  @Test

  func testSimultaneousRecentActivityAcrossBundlesFallsBackToFrontmostBundle() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 2_000_000_000)

    _ = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 0, queueTail: 0),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 10
    )

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 4, queueTail: 4),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 4, queueTail: 4),
      ],
      now: 20
    )

    #expect(roots == ["/Applications/ConsumerA.app"])
  }

  @Test

  func testInactiveRecentClientAgesOut() {
    var tracker = ForegroundConsumerActivityTracker(activeRetentionNanoseconds: 5)

    _ = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 10, queueTail: 10),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 10
    )

    let roots = tracker.consumerBundleRootPaths(
      frontmostBundleRootPath: "/Applications/ConsumerA.app",
      clients: [
        .sample(id: 1, bundle: "/Applications/ConsumerA.app", queueHead: 10, queueTail: 10),
        .sample(id: 2, bundle: "/Applications/ConsumerB.app", queueHead: 0, queueTail: 0),
      ],
      now: 20
    )

    #expect(roots == ["/Applications/ConsumerA.app"])
  }
}

private extension ForegroundConsumerClientSample {
  static func sample(
    id: UInt64,
    bundle: String,
    queueHead: Int?,
    queueTail: Int?,
    opened: Bool = true,
    suspended: Bool = false
  ) -> Self {
    .init(
      clientID: id,
      bundleRootPath: bundle,
      isOpened: opened,
      isSuspended: suspended,
      activitySignature: .init(
        queueHead: queueHead,
        queueTail: queueTail,
        queueEntries: 0,
        getReportCount: 0,
        setReportCount: 0,
        setReportErrorCount: 0
      )
    )
  }
}
