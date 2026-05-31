# Contributing

## Setup

OpenJoystickDriver has two common workflows:

- Swift package work (parsers, profiles, tests): no signing required.
- App/daemon + DriverKit extension work: requires signing/provisioning; use
  `./scripts/ojd`.

For app/daemon + DriverKit extension development, you must use the `./scripts/ojd`
signing flow; you must not try to hand-run Xcode signing steps.

Start here:

- `scripts/README.md` for signing/provisioning and release packaging
- `./scripts/ojd rebuild dev` to install a signed dev build into `/Applications`

Swift package (no signing required):

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
brew install libusb
swift build
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

Check the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues)
for open tasks. The most common contribution is adding support for a new
controller.

---

## Adding a controller

1. Identify the device class.

Run:

```bash
system_profiler SPUSBDataType
```

Check `bDeviceClass`:

- `0xff` (255): vendor-specific (often GIP for Xbox-compatible hardware)
- `0x03` (3): standard HID

2. Add the runtime profile.

Add one runtime profile under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.
VID, PID, endpoint, and packet values must be decimal integers. Use existing
profiles such as `gamesir-g7-se.json` and `flydigi-vader-5s.json` as current
format examples.

3. Add a device schema.

If the controller is vendor-specific/GIP, you must add a matching device schema
under `Resources/Schemas/Devices/`. For standard HID controllers, a device schema
is optional but encouraged.

4. Implement a parser only when the protocol is new.

New parsers go in `Sources/OpenJoystickDriverKit/Protocol/Parsers/` and must
conform to the `InputParser` protocol. Use `GIPParser.swift`, `Xbox360Parser.swift`,
and `DS4Parser.swift` as references.

5. Add tests.

Add parser, profile, or report-format tests under `Tests/OpenJoystickDriverKitTests/`.
Hardware-only checks must be guarded or expressed as diagnostics so they can
skip cleanly without local device access.

6. Validate.

```bash
./scripts/ojd validate profiles
swift test
```

---

## Code rules

- **Swift 6.2 strict concurrency.** All warnings are errors. You must not use
  `nonisolated(unsafe)` unless it is required; justify it in a comment.
- **SwiftLint zero-suppression policy.** You must not add `// swiftlint:disable`.
  Fix the lint issue instead. Exception: `@objc` callbacks that cannot satisfy a
  rule; document the reason in a same-line comment.
- **Decimal JSON only.** You must use decimal integers for VID/PID, command codes,
  and all other numeric values. You must not use hex numbers in JSON.
- **`debugPrint` only.** You must not use `print` or `swift-log`.
- **Fault isolation.** One parser error must not affect other controllers. You
  must log and skip parser errors; you must not propagate them upward.
- **macOS 10.15 runtime target.** Avoid broad availability rewrites unless the
  touched API requires it.

---

## Pull requests

- One logical change per PR.
- If you're adding a controller you own, you must test it with real hardware and
  say so in the PR description.
- If you're adding a controller you do not own (based on specs or packet
  captures), you must say so.
- You must describe what you tested. Example: "I pressed every button and checked
  output with `--headless run`."

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

The daemon and GUI communicate over XPC (`com.openjoystickdriver.xpc`). If you
add a new capability that the GUI or CLI must expose, add it to
`Sources/OpenJoystickDriverKit/XPC/XPCProtocol.swift` first.
