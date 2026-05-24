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
        .product(name: "SwiftUSB", package: "SwiftUSB"),
      ],
      path: "Tests/OpenJoystickDriverKitTests"
    ),
  ]
)
