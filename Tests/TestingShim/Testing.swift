/// Package-local shim that prevents SwiftPM's generated test runner from
/// linking Apple's Swift Testing framework on OJD's macOS 10.15 test path.
///
/// The repo's tests use XCTest. Newer SwiftPM runners still type-check a call to
/// `Testing.__swiftPMEntryPoint()` behind their `--testing-library swift-testing`
/// branch when any `Testing` module is importable. Providing the symbol here lets
/// that generated code compile without introducing Apple's framework dependency.
import Darwin

public func __swiftPMEntryPoint() -> Never {
  exit(0)
}
