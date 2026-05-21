// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "OpenJoystickDriver",
  platforms: [.macOS(.v10_15)],
  products: [
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
  ],
  dependencies: [
   .package(url: "https://github.com/xsyetopz/SwiftUSB.git", from: "0.1.0")
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

    // SwiftPM 6.x generates a package test runner that conditionally imports a
    // module named `Testing` whenever one is importable. On recent Xcode builds,
    // Apple's Testing.framework can require a newer OS than OJD's deployment
    // floor. The XCTest test target depends on this tiny package-local shim so
    // the generated runner resolves `import Testing` without linking Apple's
    // framework, preserving the macOS 10.15 minimum.
    .target(
      name: "Testing",
      path: "Tests/TestingShim"
    ),

    .executableTarget(
      name: "OpenJoystickDriverDaemon",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverDaemon",
      exclude: ["OpenJoystickDriverDaemon.entitlements.template"],
      linkerSettings: [
        .linkedFramework("GameController")
      ]
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
      resources: [.copy("Resources")],
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
        .linkedFramework("CoreHaptics"),
        .linkedFramework("GameController"),
      ]
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: [
        "OpenJoystickDriverKit",
        "Testing",
        .product(name: "SwiftUSB", package: "SwiftUSB"),
      ],
      path: "Tests/OpenJoystickDriverKitTests"
    ),
  ]
)
