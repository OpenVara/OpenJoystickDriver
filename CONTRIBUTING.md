# Contributing

## Setup

```bash
git clone https://github.com/OpenVara/OpenJoystickDriver.git
cd OpenJoystickDriver
brew install libusb
swift build
```

Tests that don't require hardware:

```bash
swift test --filter OpenJoystickDriverKitTests
```

Hardware integration tests require a USB controller plugged in:

```bash
swift test --filter HardwareTests
```

---

## What needs work

Check the [issue tracker](https://github.com/OpenVara/OpenJoystickDriver/issues) for open tasks. The most common contribution is adding support for a new controller.

---

## Adding a controller

**Step 1 - Identify the device class.**

Plug in the controller and run:

```bash
system_profiler SPUSBDataType
```

Look for `bDeviceClass`. If it's `0xff` (255), the controller uses a vendor-specific protocol (likely GIP for Xbox-compatible hardware). If it's `0x03` (3), it's a standard HID device.

**Step 2 - Add the device to the catalog.**

Edit `Sources/OpenJoystickDriverKit/Resources/devices.json`. VID and PID must be **decimal integers**, not hex strings.

```json
{
  "vendor_id": 13623,
  "product_id": 4112,
  "name": "Gamesir G7 SE",
  "parser": "gip"
}
```

Valid parser values: `"gip"`, `"ds4"`, `"generic_hid"`.

**Step 3 - Add a device schema (optional but useful).**

Create `Resources/Schemas/Devices/YourDevice.json` documenting the button layout and any protocol quirks. See `GamesirG7SE.json` for an example.

**Step 4 - If the controller uses a new protocol, implement a parser.**

New parsers go in `Sources/OpenJoystickDriverKit/Protocol/` and must conform to the `InputParser` protocol. Look at `GIPParser.swift` and `DS4Parser.swift` as references.

**Step 5 - Add tests.**

Add test cases to `Tests/OpenJoystickDriverKitTests/`. Tests that require hardware should be in `Modules/SwiftUSB/Tests/HardwareTests/` and use the `.serialized` trait.

---

## Code rules

- **Swift 6.2 strict concurrency.** All warnings are treated as errors. No `nonisolated(unsafe)` unless absolutely necessary and justified in a comment.
- **SwiftLint zero-suppression policy.** Don't add `// swiftlint:disable` lines. Fix the lint issue instead. The only exception is `@objc` callbacks that can't satisfy certain rules - document the reason in a comment on the same line.
- **No hex numbers in JSON files.** Use decimal integers for VID/PID, command codes, and all other numeric values.
- **`debugPrint` only.** Don't use `print` or `swift-log`.
- **One parser error must not affect other controllers.** Each `DevicePipeline` is isolated. Errors in a parser should be logged and skipped, not propagated upward.
- **macOS 13 minimum.** Don't add `#available` guards or fallbacks for older versions.

---

## Pull requests

- One logical change per PR.
- If you're adding a controller you own, mention in the PR description that you've tested it with real hardware.
- If you're adding a controller you don't own (based on specs or packet captures), say so.
- Describe what you tested. "I pressed every button and checked the output with `--headless run`" is enough.

There's no formal PR template. Just be clear about what changed and why.

---

## Project layout

```
Sources/OpenJoystickDriverKit/    Shared library: parsers, device management, output, XPC
Sources/OpenJoystickDriverDaemon/ Background daemon executable
Sources/OpenJoystickDriver/       GUI app (SwiftUI, menu bar) + CLI (--headless)
Modules/SwiftUSB/                 LibUSB wrapper for class 0xFF devices
Tests/OpenJoystickDriverKitTests/ Unit tests (no hardware required)
Modules/SwiftUSB/Tests/           Hardware integration tests
Resources/Schemas/                JSON schemas for IDE validation (not bundled at runtime)
docs/                             Protocol reference docs
scripts/                          Build, sign, install, uninstall helpers
```

The daemon and GUI communicate over XPC (`com.openjoystickdriver.xpc`). If you add a new capability that the GUI or CLI needs to expose, add it to `XPCProtocol.swift` first.
