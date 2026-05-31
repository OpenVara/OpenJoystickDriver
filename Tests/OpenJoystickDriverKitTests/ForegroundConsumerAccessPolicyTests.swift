import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerAccessPolicyTests {
  @Test
  func testAllowsOutputWhenNoConsumerAppsAreHoldingVirtualDevice() {
    #expect(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: nil,
        consumerBundleRootPaths: []
      ))
  }

  @Test

  func testAllowsOutputWhenFrontmostAppMatchesConsumerBundle() {
    let consumerA = "/Applications/ConsumerA.app"
    let consumerB = "/Applications/ConsumerB.app"

    #expect(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: consumerA,
        consumerBundleRootPaths: [consumerA, consumerB]
      ))
  }

  @Test

  func testSuppressesOutputWhenFrontmostAppDoesNotMatchAnyConsumerBundle() {
    #expect(!(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: "/Applications/Safari.app",
        consumerBundleRootPaths: ["/Applications/ConsumerA.app", "/Applications/ConsumerB.app"]
      )))
  }

  @Test

  func testSuppressesOutputWhenConsumerExistsButFrontmostAppIsUnknown() {
    #expect(!(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: nil,
        consumerBundleRootPaths: ["/Applications/ConsumerA.app"]
      )))
  }
}
