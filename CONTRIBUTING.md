# Contributing

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
brew install libusb
swift build
```

Tests that do not require hardware:

```bash
swift test
```

Hardware-facing tests and diagnostics require a USB controller plugged in. Use
the focused diagnostics that match your change, for example:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose sdl3 --seconds 5
```

---

## What needs work

Check the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues) for open tasks. The most common contribution is adding support for a new controller.

---

## Adding a controller

**Step 1 - Identify the device class.**

Plug in the controller and run:

```bash
system_profiler SPUSBDataType
```

Look for `bDeviceClass`. If it's `0xff` (255), the controller uses a vendor-specific protocol (likely GIP for Xbox-compatible hardware). If it's `0x03` (3), it's a standard HID device.

**Step 2 - Add the runtime profile.**

Add one runtime profile under
`Sources/OpenJoystickDriverKit/Resources/Controllers/`. VID, PID, endpoint, and
packet values must be decimal integers. Use existing profiles such as
`gamesir-g7-se.json` and `flydigi-vader-5s.json` as current format examples.

**Step 3 - Add a device schema (optional but useful).**

Create `Resources/Schemas/Devices/YourDevice.json` documenting the button layout and any protocol quirks. See `GamesirG7SE.json` for an example.

**Step 4 - If the controller uses a new protocol, implement a parser.**

New parsers go in `Sources/OpenJoystickDriverKit/Protocol/Parsers/` and must
conform to the `InputParser` protocol. Look at `GIPParser.swift`,
`Xbox360Parser.swift`, and `DS4Parser.swift` as references.

**Step 5 - Add tests.**

Add parser, profile, or report-format tests under
`Tests/OpenJoystickDriverKitTests/`. Hardware-only checks should be guarded or
expressed as diagnostics so they can skip cleanly without local device access.

---

## Code rules

- **Swift 6.2 strict concurrency.** All warnings are treated as errors. No `nonisolated(unsafe)` unless absolutely necessary and justified in a comment.
- **SwiftLint zero-suppression policy.** Don't add `// swiftlint:disable` lines. Fix the lint issue instead. The only exception is `@objc` callbacks that can't satisfy certain rules - document the reason in a comment on the same line.
- **No hex numbers in JSON files.** Use decimal integers for VID/PID, command codes, and all other numeric values.
- **`debugPrint` only.** Don't use `print` or `swift-log`.
- **One parser error must not affect other controllers.** Each `DevicePipeline` is isolated. Errors in a parser should be logged and skipped, not propagated upward.
- **macOS 10.15 runtime target.** Avoid broad availability rewrites unless the touched API requires it.

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
Tests/OpenJoystickDriverKitTests/ Unit tests (no hardware required)
Resources/Schemas/                JSON schemas and per-device schema files
docs/COMPATIBILITY_LAYERS.md      Consumer-visible compatibility mappings
scripts/                          Build, sign, install, uninstall helpers
```

The daemon and GUI communicate over XPC (`com.openjoystickdriver.xpc`). If you add a new capability that the GUI or CLI needs to expose, add it to `XPCProtocol.swift` first.
