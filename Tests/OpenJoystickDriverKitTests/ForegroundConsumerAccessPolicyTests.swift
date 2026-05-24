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
    let parsec = "/Applications/Parsec.app"
    let pcsx2 = "/Applications/PCSX2.app"

    #expect(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: parsec,
        consumerBundleRootPaths: [parsec, pcsx2]
      ))
  }

  @Test

  func testSuppressesOutputWhenFrontmostAppDoesNotMatchAnyConsumerBundle() {
    #expect(!(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: "/Applications/Safari.app",
        consumerBundleRootPaths: ["/Applications/Parsec.app", "/Applications/PCSX2.app"]
      )))
  }

  @Test

  func testSuppressesOutputWhenConsumerExistsButFrontmostAppIsUnknown() {
    #expect(!(ForegroundConsumerAccessPolicy.allowsOutput(
        frontmostBundleRootPath: nil,
        consumerBundleRootPaths: ["/Applications/Parsec.app"]
      )))
  }
}
