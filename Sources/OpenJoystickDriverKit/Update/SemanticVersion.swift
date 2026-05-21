import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
  public let major: Int
  public let minor: Int
  public let patch: Int
  public let prerelease: [String]

  public init?(_ value: String) {
    var version = value
    if version.first == "v" || version.first == "V" {
      version.removeFirst()
    }

    if let buildStart = version.firstIndex(of: "+") {
      let build = String(version[version.index(after: buildStart)...])
      guard Self.isValidBuildMetadata(build) else { return nil }
      version = String(version[..<buildStart])
    }

    let versionAndPrerelease = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard let core = versionAndPrerelease.first else { return nil }

    let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
    guard numbers.count == 3,
          Self.isValidNumericIdentifier(String(numbers[0])),
          Self.isValidNumericIdentifier(String(numbers[1])),
          Self.isValidNumericIdentifier(String(numbers[2])),
          let major = Int(numbers[0]),
          let minor = Int(numbers[1]),
          let patch = Int(numbers[2]),
          major >= 0,
          minor >= 0,
          patch >= 0 else {
      return nil
    }

    let prerelease: [String]
    if versionAndPrerelease.count == 2 {
      prerelease = versionAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      guard !prerelease.isEmpty, prerelease.allSatisfy(Self.isValidIdentifier) else { return nil }
    } else {
      prerelease = []
    }

    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    return comparePrerelease(lhs.prerelease, rhs.prerelease) == .orderedAscending
  }

  private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
    if lhs.isEmpty && rhs.isEmpty { return .orderedSame }
    if lhs.isEmpty { return .orderedDescending }
    if rhs.isEmpty { return .orderedAscending }

    for index in 0..<min(lhs.count, rhs.count) {
      let comparison = compareIdentifier(lhs[index], rhs[index])
      if comparison != .orderedSame { return comparison }
    }

    if lhs.count == rhs.count { return .orderedSame }
    return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
  }

  private static func compareIdentifier(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let lhsIsNumber = Self.isNumericIdentifier(lhs)
    let rhsIsNumber = Self.isNumericIdentifier(rhs)

    switch (lhsIsNumber, rhsIsNumber) {
    case (true, true):
      if lhs.count != rhs.count {
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
      }
      let comparison = lhs.compare(rhs, options: [], range: nil, locale: Locale(identifier: "en_US_POSIX"))
      if comparison == .orderedSame { return .orderedSame }
      return comparison == .orderedAscending ? .orderedAscending : .orderedDescending
    case (true, false):
      return .orderedAscending
    case (false, true):
      return .orderedDescending
    case (false, false):
      let comparison = lhs.compare(rhs, options: [], range: nil, locale: Locale(identifier: "en_US_POSIX"))
      if comparison == .orderedSame { return .orderedSame }
      return comparison == .orderedAscending ? .orderedAscending : .orderedDescending
    }
  }

  private static func isValidIdentifier(_ identifier: String) -> Bool {
    guard !identifier.isEmpty else { return false }
    guard identifier.unicodeScalars.allSatisfy(Self.isValidIdentifierScalar) else { return false }
    return !Self.isNumericIdentifierWithLeadingZero(identifier)
  }

  private static func isValidBuildMetadata(_ buildMetadata: String) -> Bool {
    let identifiers = buildMetadata.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
      !identifier.isEmpty && identifier.unicodeScalars.allSatisfy(Self.isValidIdentifierScalar)
    }
  }

  private static func isValidNumericIdentifier(_ identifier: String) -> Bool {
    Self.isNumericIdentifier(identifier) && !Self.isNumericIdentifierWithLeadingZero(identifier)
  }

  private static func isNumericIdentifier(_ identifier: String) -> Bool {
    !identifier.isEmpty && identifier.unicodeScalars.allSatisfy { scalar in
      ("0"..."9").contains(scalar)
    }
  }

  private static func isNumericIdentifierWithLeadingZero(_ identifier: String) -> Bool {
    identifier.count > 1 && identifier.first == "0" && Self.isNumericIdentifier(identifier)
  }

  private static func isValidIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
      ("0"..."9").contains(scalar) ||
      ("A"..."Z").contains(scalar) ||
      ("a"..."z").contains(scalar) ||
      scalar == "-"
  }
}
