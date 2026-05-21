import XCTest
@testable import OpenJoystickDriverKit

final class SemanticVersionTests: XCTestCase {
  func testParsesVersionWithLeadingVAndPrerelease() throws {
    let version = try XCTUnwrap(SemanticVersion("v0.2.0-rc.1"))
    XCTAssertEqual(version.major, 0)
    XCTAssertEqual(version.minor, 2)
    XCTAssertEqual(version.patch, 0)
    XCTAssertEqual(version.prerelease, ["rc", "1"])
  }

  func testParsesVersionWithUppercaseLeadingV() throws {
    let version = try XCTUnwrap(SemanticVersion("V0.2.0"))
    XCTAssertEqual(version.major, 0)
    XCTAssertEqual(version.minor, 2)
    XCTAssertEqual(version.patch, 0)
    XCTAssertEqual(version.prerelease, [])
  }

  func testBuildMetadataIsIgnoredForComparison() throws {
    let plain = try XCTUnwrap(SemanticVersion("0.2.0"))
    let withBuild = try XCTUnwrap(SemanticVersion("0.2.0+20260521"))
    XCTAssertEqual(plain, withBuild)
  }

  func testSemVerPrecedenceExamples() throws {
    let versions = try [
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-alpha.beta",
      "1.0.0-beta",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0-rc.1",
      "1.0.0"
    ].map { try XCTUnwrap(SemanticVersion($0)) }

    for (older, newer) in zip(versions, versions.dropFirst()) {
      XCTAssertLessThan(older, newer)
      XCTAssertFalse(newer < older)
      XCTAssertNotEqual(older, newer)
    }
  }

  func testNumericPrereleaseIdentifiersSortBeforeAlphanumericIdentifiers() throws {
    let numeric = try XCTUnwrap(SemanticVersion("1.0.0-1"))
    let alphanumeric = try XCTUnwrap(SemanticVersion("1.0.0-alpha"))
    XCTAssertLessThan(numeric, alphanumeric)
  }

  func testNumericPrereleaseIdentifiersSortNumerically() throws {
    let rc2 = try XCTUnwrap(SemanticVersion("0.2.0-rc.2"))
    let rc10 = try XCTUnwrap(SemanticVersion("0.2.0-rc.10"))
    XCTAssertLessThan(rc2, rc10)
  }

  func testStableReleaseSortsAfterPrerelease() throws {
    let rc = try XCTUnwrap(SemanticVersion("0.2.0-rc.1"))
    let stable = try XCTUnwrap(SemanticVersion("0.2.0"))
    XCTAssertLessThan(rc, stable)
  }

  func testPatchReleaseSortsAfterOlderMinor() throws {
    let old = try XCTUnwrap(SemanticVersion("0.1.9"))
    let new = try XCTUnwrap(SemanticVersion("0.2.0"))
    XCTAssertLessThan(old, new)
  }

  func testInvalidVersionsReturnNil() {
    XCTAssertNil(SemanticVersion("latest"))
    XCTAssertNil(SemanticVersion("0.2"))
  }

  func testRejectsNumericIdentifiersWithLeadingZeroes() {
    XCTAssertNil(SemanticVersion("01.2.3"))
    XCTAssertNil(SemanticVersion("1.02.3"))
    XCTAssertNil(SemanticVersion("1.2.03"))
    XCTAssertNil(SemanticVersion("1.0.0-01"))
    XCTAssertNil(SemanticVersion("1.0.0-alpha.01"))
  }

  func testRejectsInvalidPrereleaseIdentifiers() {
    XCTAssertNil(SemanticVersion("1.0.0-"))
    XCTAssertNil(SemanticVersion("1.0.0-alpha..1"))
    XCTAssertNil(SemanticVersion("1.0.0-alpha."))
    XCTAssertNil(SemanticVersion("1.0.0-.alpha"))
    XCTAssertNil(SemanticVersion("1.0.0-alpha_beta"))
  }

  func testRejectsInvalidBuildMetadataIdentifiers() {
    XCTAssertNil(SemanticVersion("1.0.0+"))
    XCTAssertNil(SemanticVersion("1.0.0+build..1"))
    XCTAssertNil(SemanticVersion("1.0.0+build."))
    XCTAssertNil(SemanticVersion("1.0.0+.build"))
    XCTAssertNil(SemanticVersion("1.0.0+build_1"))
  }

  func testComparatorConsistencyWithEquatable() throws {
    let lhs = try XCTUnwrap(SemanticVersion("1.0.0+build.1"))
    let rhs = try XCTUnwrap(SemanticVersion("1.0.0+build.2"))
    XCTAssertEqual(lhs, rhs)
    XCTAssertFalse(lhs < rhs)
    XCTAssertFalse(rhs < lhs)
  }
}
