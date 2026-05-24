import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerClientOwnerTests {
  @Test
  func testParsesPIDFromIORegistryCreatorString() {
    #expect(ForegroundConsumerClientOwner.pid(from: "pid 30617, Google Chrome") == 30_617)
  }

  @Test

  func testRejectsMalformedIORegistryCreatorString() {
    #expect(ForegroundConsumerClientOwner.pid(from: "Google Chrome") == nil)
    #expect(ForegroundConsumerClientOwner.pid(from: "pid , Google Chrome") == nil)
  }

  @Test

  func testParsesPIDFromNSNumberAndInt() {
    let bridgedInt: Any = 1234
    let bridgedZero: Any = 0
    #expect(ForegroundConsumerClientOwner.pid(from: bridgedInt) == 1234)
    #expect(ForegroundConsumerClientOwner.pid(from: 5678) == 5678)
    #expect(ForegroundConsumerClientOwner.pid(from: bridgedZero) == nil)
  }
}
