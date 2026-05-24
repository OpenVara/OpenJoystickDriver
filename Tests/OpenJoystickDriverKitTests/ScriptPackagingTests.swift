import Foundation
import Testing

struct ScriptPackagingTests {
  @Test
  func testDmgStylingAppleScriptOpensFinderDiskObject() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/ojd-package.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(!script.contains("tell volumeRoot"))
    #expect(script.contains("set volumeName to \"OpenJoystickDriver\""))
    #expect(script.contains("set volumeDisk to disk volumeName"))
    #expect(script.contains("open volumeDisk"))
  }

  @Test
  func testBuildScriptRequiresInstalledSigningIdentity() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/ojd-build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("security find-identity -v -p codesigning"))
    #expect(script.contains("grep -Fi \"$identity\""))
    #expect(script.contains("_codesign_identity_available \"$GUI_IDENTITY\""))
    #expect(script.contains("_codesign_identity_available \"$DAEMON_IDENTITY\""))
  }
}
