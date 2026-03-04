# OpenJoystickDriver

macOS userspace gamepad driver. Plug in a controller, remap it, use it.

---

## Background

macOS has no kernel driver for gamepads. Windows ships XInput. Linux shipped xboxdrv before merging it into the kernel as `xpad.c`. On macOS, the last maintained general-purpose solution was [Enjoyable](https://github.com/shirosaki/enjoyable), which hasn't had a commit in over a decade (Sept 18, 2015) and doesn't support modern controllers, Apple Silicon, or newer macOS versions properly.

This matters most to people running emulators (PCSX2, DuckStation, RetroArch) who want to use the controller they already own rather than buying something specifically for macOS. It also matters to game studios and engine integrators (Unity, Unreal, custom engines) that need a stable, scriptable gamepad input layer.

OpenJoystickDriver is to gamepads what [OpenTabletDriver](https://opentabletdriver.net/) is to drawing tablets: a userspace driver that doesn't require a kernel extension, with an open device registry that contributors can extend.

---

## What works

**v0.1.0**

| Feature | Status |
|---------|--------|
| Xbox One / Series controllers (GIP protocol) | Working — hardware verified on Gamesir G7 SE |
| DualShock 4 (USB) | Implemented, untested (no PS4 hardware) |
| Generic USB HID gamepads | Basic fallback (reports standard HID usage page) |
| Button remapping | Working — JSON profiles per VID/PID |
| Stick → mouse, D-pad → arrow keys | Working |
| Menu bar app (SwiftUI) | Working |
| CLI (`--headless`) | Working |
| LaunchAgent (auto-start on login) | Working |
| Bluetooth | Not implemented |
| DualSense (PS5) | Not implemented |
| Switch Pro Controller | Not implemented |

---

## Requirements

- macOS 13 (Ventura) or later
- [libusb](https://libusb.info/) — required for Xbox/GIP controllers
- Xcode Command Line Tools or a full Xcode installation (for `swift build`)
- Two system permissions granted at first launch:
  - **Input Monitoring** — to read controller input
  - **Accessibility** — to inject keyboard/mouse events

```bash
brew install libusb
```

---

## Build and install

```bash
git clone https://github.com/OpenVara/OpenJoystickDriver.git
cd OpenJoystickDriver
./scripts/install.sh
```

This builds a universal binary (arm64 + x86_64), installs both the daemon and the GUI app to `/usr/local/bin`, and registers the daemon as a LaunchAgent so it starts on login.

To uninstall:

```bash
.build/debug/OpenJoystickDriver --headless uninstall
sudo rm /usr/local/bin/OpenJoystickDriver /usr/local/bin/OpenJoystickDriverDaemon
```

---

## Usage

**GUI:** Launch `OpenJoystickDriver` from `/usr/local/bin` or Spotlight. It runs as a menu bar app. The sidebar lists connected controllers; clicking one opens the mapping editor.

**CLI:**

```bash
# Check permission states
OpenJoystickDriver --headless status

# List connected controllers
OpenJoystickDriver --headless list

# Run the driver interactively (foreground, logs to stdout)
OpenJoystickDriver --headless run

# Print macOS version, permissions, USB devices, troubleshooting tips
OpenJoystickDriver --headless diagnose

# Profile management
OpenJoystickDriver --headless profile list
OpenJoystickDriver --headless profile show --vid 13623 --pid 4112
```

**Note on USB access for Xbox/GIP controllers:** LibUSB requires either a code-signed binary with the USB Device entitlement or `sudo`. For development builds, use:

```bash
sudo .build/debug/OpenJoystickDriverDaemon
```

Production builds via `scripts/build-release.sh` use a Developer ID certificate with the entitlement included.

---

## Architecture

Two input paths, one per USB device class:

```
USB Class 0xFF (Vendor-Specific)   →  LibUSB / SwiftUSB  →  GIPParser
USB Class 0x03 (HID)               →  IOKit / IOHIDManager  →  DS4Parser or GenericHIDParser
```

Both paths feed into a `DevicePipeline` actor — one per connected controller. Pipelines are isolated: a crash or parse error in one controller's pipeline doesn't affect the others.

The daemon exposes an XPC service (`com.openjoystickdriver.xpc`). The GUI and CLI connect to it for device listing, status queries, and profile changes. The daemon never depends on the GUI being open.

Profiles are stored at `~/Library/Application Support/OpenJoystickDriver/profiles/{VID}-{PID}.json`.

---

## Adding controller support

Device support lives in two places:

- `Sources/OpenJoystickDriverKit/Resources/devices.json` — VID/PID catalog and parser assignment
- `Resources/Schemas/Devices/` — per-device field layouts (for documentation and validation)

To add a new controller:

1. Add an entry to `devices.json` with the VID, PID, and parser type (`"gip"`, `"ds4"`, or `"generic_hid"`)
2. If it uses a non-standard protocol, implement a new `InputParser` conformance in `Sources/OpenJoystickDriverKit/Protocol/`
3. Add a device schema file to `Resources/Schemas/Devices/` (optional but helpful)
4. Add tests in `Tests/OpenJoystickDriverKitTests/`

VID and PID values in JSON must be decimal integers, not hex strings.

---

## Development

```bash
# Build (debug)
swift build

# Run tests (no hardware required)
swift test --filter OpenJoystickDriverKitTests

# Run hardware integration tests (requires a controller)
swift test --filter HardwareTests

# Build + ad-hoc sign for local testing
./scripts/sign-dev.sh
```

Swift 6.2 strict concurrency is enforced. All warnings are errors. SwiftLint runs as a build plugin with zero-suppression policy.

---

## License

MIT — see [LICENSE](LICENSE).
