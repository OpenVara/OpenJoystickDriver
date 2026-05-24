@testable import OpenJoystickDriverKit
import Testing

struct SemanticVersionTests {
  @Test
  func testParsesVersionWithLeadingVAndPrerelease() throws {
    let version = try #require(SemanticVersion("v0.2.0-rc.1"))
    #expect(version.major == 0)
    #expect(version.minor == 2)
    #expect(version.patch == 0)
    #expect(version.prerelease == ["rc", "1"])
  }

  @Test

  func testParsesVersionWithUppercaseLeadingV() throws {
    let version = try #require(SemanticVersion("V0.2.0"))
    #expect(version.major == 0)
    #expect(version.minor == 2)
    #expect(version.patch == 0)
    #expect(version.prerelease == [])
  }

  @Test

  func testBuildMetadataIsIgnoredForComparison() throws {
    let plain = try #require(SemanticVersion("0.2.0"))
    let withBuild = try #require(SemanticVersion("0.2.0+20260521"))
    #expect(plain == withBuild)
  }

  @Test

  func testSemVerPrecedenceExamples() throws {
    let versions = try [
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-alpha.beta",
      "1.0.0-beta",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0-rc.1",
      "1.0.0",
    ].map { try #require(SemanticVersion($0)) }

    for (older, newer) in zip(versions, versions.dropFirst()) {
      #expect(older < newer)
      #expect(!(newer < older))
      #expect(older != newer)
    }
  }

  @Test

  func testNumericPrereleaseIdentifiersSortBeforeAlphanumericIdentifiers() throws {
    let numeric = try #require(SemanticVersion("1.0.0-1"))
    let alphanumeric = try #require(SemanticVersion("1.0.0-alpha"))
    #expect(numeric < alphanumeric)
  }

  @Test

  func testNumericPrereleaseIdentifiersSortNumerically() throws {
    let rc2 = try #require(SemanticVersion("0.2.0-rc.2"))
    let rc10 = try #require(SemanticVersion("0.2.0-rc.10"))
    #expect(rc2 < rc10)
  }

  @Test

  func testStableReleaseSortsAfterPrerelease() throws {
    let rc = try #require(SemanticVersion("0.2.0-rc.1"))
    let stable = try #require(SemanticVersion("0.2.0"))
    #expect(rc < stable)
  }

  @Test

  func testPatchReleaseSortsAfterOlderMinor() throws {
    let old = try #require(SemanticVersion("0.1.9"))
    let new = try #require(SemanticVersion("0.2.0"))
    #expect(old < new)
  }

  @Test

  func testInvalidVersionsReturnNil() {
    #expect(SemanticVersion("latest") == nil)
    #expect(SemanticVersion("0.2") == nil)
  }

  @Test

  func testRejectsNumericIdentifiersWithLeadingZeroes() {
    #expect(SemanticVersion("01.2.3") == nil)
    #expect(SemanticVersion("1.02.3") == nil)
    #expect(SemanticVersion("1.2.03") == nil)
    #expect(SemanticVersion("1.0.0-01") == nil)
    #expect(SemanticVersion("1.0.0-alpha.01") == nil)
  }

  @Test

  func testRejectsInvalidPrereleaseIdentifiers() {
    #expect(SemanticVersion("1.0.0-") == nil)
    #expect(SemanticVersion("1.0.0-alpha..1") == nil)
    #expect(SemanticVersion("1.0.0-alpha.") == nil)
    #expect(SemanticVersion("1.0.0-.alpha") == nil)
    #expect(SemanticVersion("1.0.0-alpha_beta") == nil)
  }

  @Test

  func testRejectsInvalidBuildMetadataIdentifiers() {
    #expect(SemanticVersion("1.0.0+") == nil)
    #expect(SemanticVersion("1.0.0+build..1") == nil)
    #expect(SemanticVersion("1.0.0+build.") == nil)
    #expect(SemanticVersion("1.0.0+.build") == nil)
    #expect(SemanticVersion("1.0.0+build_1") == nil)
  }

  @Test

  func testComparatorConsistencyWithEquatable() throws {
    let lhs = try #require(SemanticVersion("1.0.0+build.1"))
    let rhs = try #require(SemanticVersion("1.0.0+build.2"))
    #expect(lhs == rhs)
    #expect(!(lhs < rhs))
    #expect(!(rhs < lhs))
  }
}
