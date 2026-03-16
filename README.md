# OpenJoystickDriver

macOS userspace gamepad driver. Plug in a controller, remap it, use it.

---

## Background

macOS has no kernel driver for gamepads. Windows ships XInput. Linux merged `xpad.c` into the kernel. On macOS, the last maintained general-purpose solution was [Enjoyable](https://github.com/shirosaki/enjoyable), which hasn't had a commit since 2015 and doesn't support modern controllers, Apple Silicon, or current macOS.

This matters most to game studios and engine integrators (Unity, Unreal, custom engines) that need a stable, scriptable gamepad input layer, and to emulator users who want to use the controller they already own.

OpenJoystickDriver is to gamepads what [OpenTabletDriver](https://opentabletdriver.net/) is to drawing tablets: a userspace driver that requires no kernel extension, with an open device registry that contributors can extend.

---

## What works

| Feature | Status |
|---------|--------|
| Xbox One / Series controllers (GIP protocol) | Working - hardware verified on Gamesir G7 SE |
| GIP authentication (CMD 0x06 sub-protocol) | Working - state machine with dummy auth payloads |
| Virtual HID gamepad (DriverKit extension) | Working - production output path on macOS 13+ |
| Virtual HID gamepad (IOHIDUserDevice fallback) | Working - fallback when dext not installed |
| DualShock 4 (USB) | Implemented, untested (no PS4 hardware) |
| Generic USB HID gamepads | Basic fallback (standard HID usage page) |
| Button remapping | Working - JSON profiles per VID/PID |
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
- [libusb](https://libusb.info/) - required for Xbox/GIP controllers
- Xcode Command Line Tools or a full Xcode installation (for `swift build`)

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

This builds release binaries, installs to `/usr/local/bin`, and registers the daemon as a LaunchAgent so it starts automatically on login.

To uninstall:

```bash
./scripts/uninstall.sh
```

---

## Permissions

One system permission is required:

- **Input Monitoring** (`System Settings > Privacy > Input Monitoring`) - to read controller input

Grant it to the **daemon binary** (`OpenJoystickDriverDaemon`), not the GUI app.

Accessibility permission is **not** needed — the driver injects gamepad input via a virtual HID device (DriverKit extension or IOHIDUserDevice fallback), not CGEvents.

> **Note for development builds:** Ad-hoc signed binaries get a new code identity on every `swift build`. macOS ties TCC grants to **the** binary's code identity, so permissions reset after each rebuild. After rebuilding, re-grant both permissions and use `--headless restart` or the **Restart Daemon** button in the app. The Permissions view detects this state and shows a prompt automatically.
>
> To avoid this, sign with a real Apple Development certificate:
>
> ```bash
> export CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
> ./scripts/build-dev.sh
> ```
>
> Find your identity: `security find-identity -v -p codesigning`

---

## Usage

### GUI

Launch `OpenJoystickDriver` from `/usr/local/bin` or Spotlight. It runs as a menu bar app.

- **Sidebar** - lists connected controllers and navigation links for Permissions and Diagnostics
- **Mapping tab** - remap any button to a keyboard key; configure stick deadzone, mouse sensitivity, scroll sensitivity
- **Info tab** - VID, PID, protocol, connection details
- **Permissions** - per-permission status cards with deep links to System Settings; shows a restart prompt when permissions reset after a rebuild
- **Diagnostics** - daemon lifecycle controls (install / start / restart / uninstall), log path, troubleshooting tips, copy-to-clipboard diagnostics

### CLI

All CLI commands use the `--headless` flag:

```bash
# Check permission states (via daemon if running, direct otherwise)
OpenJoystickDriver --headless status

# List connected controllers
OpenJoystickDriver --headless list

# Run the driver interactively (foreground, Ctrl+C to stop)
OpenJoystickDriver --headless run

# Print macOS version, permissions, USB devices, troubleshooting tips
OpenJoystickDriver --headless diagnose

# Daemon lifecycle
OpenJoystickDriver --headless install    # Register as LaunchAgent
OpenJoystickDriver --headless start      # Start the daemon
OpenJoystickDriver --headless restart    # Restart the daemon
OpenJoystickDriver --headless uninstall  # Remove LaunchAgent

# Profile management
OpenJoystickDriver --headless profile list
OpenJoystickDriver --headless profile show 13623:4112
OpenJoystickDriver --headless profile set  13623:4112 A Return
OpenJoystickDriver --headless profile set  13623:4112 LB [
OpenJoystickDriver --headless profile reset 13623:4112
```

VID and PID in CLI commands are **decimal** integers (e.g. `13623:4112` for Gamesir G7 SE).

`profile set` accepts a button name (case-insensitive: `a`, `b`, `x`, `y`, `start`, `back`, `guide`, `lb`, `rb`, `dpadup`, `dpaddown`, `dpadleft`, `dpadright`) and either a key name (`Return`, `Escape`, `Space`) or a raw macOS keycode integer.

---

## Architecture

### Input

Two input paths, one per USB device class:

```
USB Class 0xFF (Vendor-Specific)  →  LibUSB / SwiftUSB    →  GIPParser (+ GIPAuthHandler)
USB Class 0x03 (HID)              →  IOKit / IOHIDManager  →  DS4Parser or GenericHIDParser
```

Both paths feed into a `DevicePipeline` actor - one per connected controller. Pipelines are isolated: an error in one controller's pipeline doesn't affect the others.

GIP controllers (Xbox One / Series) require a CMD 0x06 authentication handshake before they send input. `GIPAuthHandler` implements the state machine with dummy auth payloads (lenient enforcement allows cryptographically empty responses).

### Output

```
DextOutputDispatcher  →  DriverKit extension (IOUserHIDDevice + user-client IPC)
```

The DriverKit extension (`OpenJoystickVirtualHIDDevice`) registers as a system HID device and accepts 13-byte input reports from the daemon via user-client IPC. If the extension is not yet loaded, the dispatcher auto-retries on each input event until the connection succeeds.

### IPC and profiles

The daemon exposes an XPC service (`com.openjoystickdriver.xpc`). The GUI and CLI connect to it for device listing, status queries, and profile changes. The daemon never depends on the GUI being open.

Profiles are stored at `~/Library/Application Support/OpenJoystickDriver/profiles/{VID}-{PID}.json`.

---

## Adding controller support

Device support lives in two places:

- `Sources/OpenJoystickDriverKit/Resources/devices.json` - VID/PID catalog and parser assignment
- `Resources/Schemas/Devices/` - per-device field layouts (for documentation and validation)

To add a new controller:

1. Add an entry to `devices.json` with the VID, PID, and parser type (`"gip"`, `"ds4"`, or `"generic_hid"`)
2. If it uses a non-standard protocol, implement a new `InputParser` conformance in `Sources/OpenJoystickDriverKit/Protocol/`
3. Add a device schema file to `Resources/Schemas/Devices/` (optional but helpful for reviewers)
4. Add tests in `Tests/OpenJoystickDriverKitTests/`

VID and PID values in JSON must be **decimal** integers, not hex strings.

---

## Development

```bash
# Build
swift build

# Run tests (no hardware required)
swift test --filter OpenJoystickDriverKitTests

# Build + ad-hoc sign both debug binaries (creates .app bundle)
./scripts/build-dev.sh

# Build + sign + immediately run the daemon (fast dev loop)
./scripts/run-dev.sh

# Build the DriverKit extension (requires provisioning profile)
./scripts/build-dext.sh

# Build universal release binaries, codesign, and notarize
./scripts/build-release.sh

# Lint
./scripts/lint.sh
```

Swift 6.2 strict concurrency is enforced. All warnings are errors. SwiftLint zero-suppression policy.

---

## License

MIT - see [LICENSE](LICENSE).
