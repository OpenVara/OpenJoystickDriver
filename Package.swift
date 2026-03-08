// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "OpenJoystickDriver",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "SwiftUSB", targets: ["SwiftUSB"]),
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
  ],
  dependencies: [],
  targets: [
    .systemLibrary(
      name: "CLibUSB",
      path: "Modules/SwiftUSB/Sources/CLibUSB",
      pkgConfig: "libusb-1.0",
      providers: [.brew(["libusb"]), .apt(["libusb-1.0-0-dev"])]
    ),

    .target(
      name: "SwiftUSB",
      dependencies: ["CLibUSB"],
      path: "Modules/SwiftUSB",
      exclude: ["Tests"]
    ),

    .target(
      name: "OpenJoystickDriverKit",
      dependencies: ["SwiftUSB", "CLibUSB"],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")]
    ),

    .executableTarget(
      name: "OpenJoystickDriverDaemon",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverDaemon",
      exclude: ["OpenJoystickDriverDaemon.entitlements"]
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriver",
      exclude: ["OpenJoystickDriver.entitlements", "App/Info.plist"],
      linkerSettings: [
        .linkedFramework("SystemExtensions"),
      ]
    ),

    .testTarget(
      name: "SwiftUSBTests",
      dependencies: ["SwiftUSB"],
      path: "Modules/SwiftUSB/Tests/SwiftUSBTests"
    ),

    .testTarget(
      name: "HardwareTests",
      dependencies: ["SwiftUSB"],
      path: "Modules/SwiftUSB/Tests/HardwareTests"
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: ["OpenJoystickDriverKit", "SwiftUSB"],
      path: "Tests/OpenJoystickDriverKitTests"
    ),
  ]
)
