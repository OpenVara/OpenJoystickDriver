// swift-tools-version:6.2
import Foundation
import PackageDescription

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
let appleDeveloperFrameworkCandidates = [
  developerDir.map { "\($0)/Platforms/MacOSX.platform/Developer/Library/Frameworks" },
  developerDir.map { "\($0)/Library/Developer/Frameworks" },
  "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
].compactMap { $0 }
let appleDeveloperLibCandidates = [
  developerDir.map { "\($0)/Library/Developer/usr/lib" },
  "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
].compactMap { $0 }
let appleDeveloperFrameworksPath =
  appleDeveloperFrameworkCandidates.first {
    FileManager.default.fileExists(atPath: "\($0)/Testing.framework")
  } ?? appleDeveloperFrameworkCandidates[0]
let appleDeveloperLibPath =
  appleDeveloperLibCandidates.first {
    FileManager.default.fileExists(atPath: "\($0)/lib_TestingInterop.dylib")
  } ?? appleDeveloperLibCandidates[0]
let appleTestingFrameworkSettings: [SwiftSetting] = [
  .unsafeFlags(["-F", appleDeveloperFrameworksPath], .when(platforms: [.macOS]))
]
let appleTestingFrameworkLinkerSettings: [LinkerSetting] = [
  .unsafeFlags(
    [
      "-F", appleDeveloperFrameworksPath,
      "-framework", "Testing",
      "-Xlinker", "-rpath",
      "-Xlinker", appleDeveloperFrameworksPath,
      "-Xlinker", "-rpath",
      "-Xlinker", appleDeveloperLibPath,
    ],
    .when(platforms: [.macOS])
  )
]

let package = Package(
  name: "OpenJoystickDriver",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
  ],
  dependencies: [
    .package(path: "../SwiftUSB"),
  ],
  targets: [
    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [.product(name: "SwiftUSB", package: "SwiftUSB")],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")],
      linkerSettings: [
        .linkedFramework("ServiceManagement")
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverDaemon",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverDaemon",
      exclude: ["OpenJoystickDriverDaemon.entitlements.template"]
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriver",
      exclude: [
        "OpenJoystickDriver.entitlements.template",
        "App/Info.plist",
        "App/com.openjoystickdriver.daemon.plist",
      ],
      linkerSettings: [
        .linkedFramework("SystemExtensions"),
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverHIDTool",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverHIDTool"
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerProbe",
      path: "Sources/OpenJoystickDriverGameControllerProbe",
      linkerSettings: [
        .linkedFramework("GameController")
      ]
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: ["OpenJoystickDriverKit", .product(name: "SwiftUSB", package: "SwiftUSB")],
      path: "Tests/OpenJoystickDriverKitTests",
      swiftSettings: appleTestingFrameworkSettings,
      linkerSettings: appleTestingFrameworkLinkerSettings
    ),
  ]
)
