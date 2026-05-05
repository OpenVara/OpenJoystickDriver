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
| Xbox One / Series controllers (GIP protocol) | Working - hardware verified on Gamesir G7 SE, Flydigi Vader 5S |
| GIP authentication (CMD 0x06 sub-protocol) | Working - state machine with dummy auth payloads |
| Flydigi Vader 5S (USB, GIP) | Working - per-device endpoint config, setConfiguration quirk |
| Virtual HID gamepad (DriverKit extension) | Working - production output path on macOS 13+ |
| Virtual HID gamepad (IOHIDUserDevice user-space) | Working - optional compatibility mode (no reboot) |
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
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd rebuild dev
```

This builds a signed app bundle and installs it to `/Applications/OpenJoystickDriver.app`.
The daemon is managed as a LaunchAgent via `SMAppService` from inside the app/CLI.

---

## Permissions

One system permission is required:

- **Input Monitoring** (`System Settings > Privacy > Input Monitoring`) - to read controller input

Grant it to the **daemon binary** (`OpenJoystickDriverDaemon`), not the GUI app.

Accessibility permission is **not** needed — the driver injects gamepad input via a virtual HID device (DriverKit extension, and optionally a user-space IOHIDUserDevice), not CGEvents.

### SDL compatibility (no reboot)

Some SDL/IOKit apps ignore virtual devices with `Transport="Virtual"` (common for DriverKit virtual HID).
If a game/emulator can *see* your controller but won’t react to inputs, enable:

- Open the OpenJoystickDriver menu bar item → `Mode` → `Compatibility`

This uses a user-space virtual controller (IOHIDUserDevice). It does not require a reboot.
When enabled, OpenJoystickDriver routes output to the user-space device (and disables DriverKit output).

> **Note for development builds:** Ad-hoc signed binaries get a new code identity on every `swift build`. macOS ties TCC grants to **the** binary's code identity, so permissions reset after each rebuild. After rebuilding, re-grant both permissions and use `--headless restart` or the **Restart Daemon** button in the app. The Permissions view detects this state and shows a prompt automatically.
>
> To avoid this, sign with a real Apple Development certificate:
>
> ```bash
> ./scripts/ojd signing configure
> ./scripts/ojd build dev
> ```
>
> Find your identity: `security find-identity -v -p codesigning`

---

## Usage

### GUI

Launch `OpenJoystickDriver` from `/usr/local/bin` or Spotlight. It runs as a menu bar app.

- The menu bar popover shows:
  - **Driver** status (and which backend is active)
  - **DriverKit** install status + errors
  - **Mode**: Auto / DriverKit / Compatibility
  - **Self-test** and a log shortcut

If the LaunchAgent daemon cannot be managed in your current session (some shells/terminal sessions can’t talk to `launchd` properly), OpenJoystickDriver automatically falls back to an **embedded backend** so the driver still works.

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

# Virtual device toggles
OpenJoystickDriver --headless userspace status
OpenJoystickDriver --headless userspace on
OpenJoystickDriver --headless userspace off

# Output routing (DriverKit / user-space / both)
OpenJoystickDriver --headless output status
OpenJoystickDriver --headless output primary
OpenJoystickDriver --headless output secondary
OpenJoystickDriver --headless output both

# Virtual device input self-test (press buttons while it runs)
OpenJoystickDriver --headless selftest 5
```

---

## PCSX2 (SDL3) on macOS

PCSX2 2.6.x uses **SDL3** for controller input on macOS. If you can see the controller in a browser gamepad tester but PCSX2 won’t react to inputs, do this:

1. Open **PCSX2 → Settings → Controllers → Global Settings**
2. Ensure **Enable SDL Input Source** is checked
3. Pick the device under **Detected Devices** (you should see `SDL-0 OpenJoystickDriver Virtual Gamepad`)
4. Bind buttons/axes under **Controller Port 1**

If the controller only appears (or only works) when you enable **Enable MFI Driver**, that indicates PCSX2 is reading it through GameController.framework instead of SDL.

To debug whether SDL is receiving events at all, build and run the SDL3 probe:

```bash
./scripts/ojd diagnose sdl3 --seconds 10
```

If the probe prints no `axis`/`button` events while you press inputs, SDL isn’t receiving input from the virtual device (PCSX2 SDL input will also fail).
Enable Compatibility mode in the menu bar app (`Mode` → `Compatibility`) and try again.

### PCSX2 is Intel (Rosetta): compare SDL3 behavior

Some PCSX2 builds ship as Intel-only and run under Rosetta. SDL input behavior can differ between:

- native arm64 SDL3
- Intel (x86_64) SDL3 under Rosetta

This repo includes a script that runs both probes back-to-back:

```bash
./scripts/ojd diagnose pcsx2-latency
```

If the native probe reports instant events but the PCSX2/Rosetta probe reports 0 devices (or very delayed events),
the bottleneck is on the PCSX2/Rosetta SDL input path, not in OpenJoystickDriver.

### If you see `setReport error: -1ffffd15`

`-1ffffd15` is `kIOReturnAborted` (`0xe00002eb`). On macOS this commonly happens during
system-extension upgrades/replacements: IOKit aborts in-flight operations and your process
ends up holding a stale handle.

Fix (fast):

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
```

If `./scripts/ojd diagnose dext` reports stale sysext copies, a reboot cleans them up.

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

Optional `devices.json` fields for USB quirks:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `input_endpoint` | int | 0x82 (130) | Interrupt IN endpoint address |
| `output_endpoint` | int | 0x02 (2) | Interrupt OUT endpoint address |
| `needs_set_configuration` | bool | false | Call `setConfiguration(1)` before claiming interface (for devices that enumerate unconfigured) |

Both `input_endpoint` and `output_endpoint` must be present together; if only one is set, the override is ignored and GIP defaults apply.

---

## Development

```bash
# One-time signing setup (macOS 26+)
./scripts/ojd signing install-profiles
./scripts/ojd signing configure

# Full rebuild + deploy (reinstalls sysext; may require reboot)
./scripts/ojd rebuild dev

# Fast rebuild (does NOT reinstall/upgrade sysext; safe during streams / no reboot)
./scripts/ojd rebuild-fast dev

# Build universal release binaries, codesign, and notarize
OJD_ENV=release ./scripts/ojd rebuild release
OJD_ENV=release ./scripts/ojd notarize submit

# Lint (requires swiftlint)
./scripts/ojd lint
```

### Signing + provisioning (macOS 26+)

macOS 26+ enforces provisioning for certain entitlements (system extension / DriverKit). This repo expects:

- Provisioning profiles installed at `~/Library/MobileDevice/Provisioning Profiles/`
- Two Keychain identities:
  - `Apple Development: …` (for dev builds + dext build step)
  - `Developer ID Application: …` (for release signing + notarization)

The Team ID in the identity name (the `(...)` suffix) must match the provisioning profile’s Team ID. If you have multiple Apple Developer teams, it’s easy to create an Apple Development cert for the “wrong” team.

Sanity-check installed profiles (safe output; no identifiers printed):

```bash
./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
```

Install profiles from `~/Documents/Profiles/` (or `~/Documents/profiles/`):

```bash
./scripts/ojd signing install-profiles
```

Generate `scripts/.env.dev` and `scripts/.env.release` automatically (no heredocs / no copy-paste):

```bash
./scripts/ojd signing configure
```

If something fails, run the signing doctor first (prints safe info only):

```bash
./scripts/ojd signing doctor
```

#### “Certificate is not trusted” (Keychain)

If Keychain Access shows “not trusted” but `security find-identity` reports the identity as **valid**, you can usually ignore the UI.

If `security find-identity` reports **0 valid identities**, you’re missing Apple’s intermediate CA certificates (WWDR / Developer ID). Get them from Apple’s Certificate Authority page and import them in Keychain Access (System keychain is fine):

Apple PKI index:

```text
https://www.apple.com/certificateauthority/
```
Then re-check:

```bash
security find-identity -v -p codesigning
```

#### “Keychain Access shows certs, but security says 0 identities”

If `security find-identity` prints `0 valid identities found` but Keychain Access shows your certs with private keys, your keychain file permissions are wrong (this can happen after migrations / restores).

Fix:

```bash
chmod 700 "$HOME/Library/Keychains"
chmod 600 "$HOME/Library/Keychains/login.keychain-db"
```

Then log out/in (or reboot), and re-run `security find-identity`.

### Notarization (release builds)

This repo uses `xcrun notarytool` with an Apple ID + an app-specific password.

Create an app-specific password at:

```text
https://account.apple.com/  → Sign-In and Security → App-Specific Passwords
```

Put the values into `scripts/.env.release`:

- `NOTARIZE_APPLE_ID="you@example.com"`
- `NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"`

Then run:

```bash
OJD_ENV=release ./scripts/ojd rebuild release
OJD_ENV=release ./scripts/ojd notarize submit
```

Swift 6.2 strict concurrency is enforced. All warnings are errors. SwiftLint zero-suppression policy.

---

## License

MIT - see [LICENSE](LICENSE).
