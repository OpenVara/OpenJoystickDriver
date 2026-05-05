# OpenJoystickDriver

OpenJoystickDriver is a macOS userspace gamepad driver. It reads physical
controllers, normalizes their reports, and exposes a virtual controller through
DriverKit or an IOHIDUserDevice compatibility backend.

The project is built for users who need a scriptable controller input layer on
macOS: emulator users, engine integrators, game studios, and contributors adding
new controller profiles.

## Status

| Area                                    | Current state                                                                        |
| --------------------------------------- | ------------------------------------------------------------------------------------ |
| macOS support                           | macOS 13 or later                                                                    |
| Xbox One / Series class USB controllers | Working through the GIP protocol                                                     |
| GameSir G7 SE                           | Hardware verified, including Xbox One HID compatibility reports                      |
| Flydigi Vader 5S                        | Supported with a per-device schema, endpoint config, and `setConfiguration(1)` quirk |
| DualShock 4 USB                         | Implemented, not hardware verified in this repo                                      |
| Generic USB HID gamepads                | Basic fallback                                                                       |
| Virtual output                          | DriverKit HID and IOHIDUserDevice compatibility mode                                 |
| GUI                                     | SwiftUI menu bar app                                                                 |
| CLI                                     | `--headless` daemon and diagnostics commands                                         |
| Bluetooth                               | Not implemented                                                                      |
| DualSense / Switch Pro                  | Not implemented                                                                      |

GameSir G7 SE was manually verified in browser Gamepad API Xbox One HID
compatibility mode as a standard `Xbox Wireless Controller` (`VID 045e`,
`PID 02ea`). The verified button layout is:

| Button | Meaning     |
| ------ | ----------- |
| `B0`   | A           |
| `B1`   | B           |
| `B2`   | X           |
| `B3`   | Y           |
| `B4`   | LB          |
| `B5`   | RB          |
| `B6`   | LT          |
| `B7`   | RT          |
| `B8`   | View        |
| `B9`   | Menu        |
| `B10`  | L3          |
| `B11`  | R3          |
| `B12`  | D-pad Up    |
| `B13`  | D-pad Down  |
| `B14`  | D-pad Left  |
| `B15`  | D-pad Right |
| `B16`  | Xbox/Home   |

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or full Xcode
- `libusb`

```bash
brew install libusb
xcode-select --install
```

The Swift package uses Swift tools version 6.2 and Swift Testing. CI currently
runs on macOS 26 so the compiler, SDK, and Apple `Testing.framework` match.

## Quick Start

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver

./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd rebuild dev
```

The dev rebuild creates a signed app bundle and installs it to
`/Applications/OpenJoystickDriver.app`. The daemon is managed through
`SMAppService`; do not bootstrap it manually with `launchctl`.

## Permissions

Grant **Input Monitoring** to the daemon binary:

```text
/Applications/OpenJoystickDriver.app/Contents/Library/LoginItems/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon
```

Accessibility permission is not required for normal virtual-controller output.

Development builds signed ad hoc can lose TCC grants after every rebuild because
macOS ties permissions to the binary code identity. Use a real Apple Development
identity for stable local testing.

## Running

Use the app from `/Applications/OpenJoystickDriver.app`, or run the CLI from the
app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
```

Common developer commands:

```bash
./scripts/ojd rebuild dev
./scripts/ojd rebuild-fast dev
./scripts/ojd validate profiles
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
swift test
```

Release and signing details live in [scripts/README.md](scripts/README.md).

## Controller Profiles

Runtime controller profiles live here:

```text
Sources/OpenJoystickDriverKit/Resources/Controllers/
```

Device schemas live here:

```text
Resources/Schemas/Devices/
```

Every controller profile must use a repo URL for `$schema`, not a local file URL.
GIP controller profiles must also have a matching device schema. Validate both
with:

```bash
./scripts/ojd validate profiles
```

Controller profiles use decimal VID/PID and endpoint values. Protocol metadata
such as `variant` and mapping flags follows the xpad-style device family model so
new Xbox-class devices can be added without hardcoding parser quirks.

## Architecture

Input paths:

```text
USB vendor-specific devices -> LibUSB / SwiftUSB -> GIPParser
USB HID devices             -> IOHIDManager      -> DS4Parser or GenericHIDParser
```

Output paths:

```text
DriverKit HID backend       -> private OJD relay / fallback diagnostics
IOHIDUserDevice backend     -> consumer-facing virtual controller profiles
```

If macOS keeps an old DriverKit process alive after a dext upgrade, browser and
SDL consumers can see a stale extra virtual controller. Repair that state with:

```bash
./scripts/ojd repair stale-dext
```

The repair command only kills `OpenJoystickVirtualHID` processes whose executable
path does not match the newest installed `com.openjoystickdriver.VirtualHIDDevice`
copy under `/Library/SystemExtensions`.

Compatibility mode has four first-class user-space HID profiles:

- `sdl-macos`: default for macOS SDL consumers such as Steam and PCSX2. It uses
  an OJD-owned identity plus an explicit SDL mapping.
- `generic-hid`: OJD-owned HID GamePad identity for apps that inspect the HID
  descriptor directly.
- `x360-hid`: experimental Xbox 360 HID hardware-spoof profile.
- `xone-hid`: experimental Xbox One HID hardware-spoof profile.

SDL consumers need a game controller mapping for the SDL macOS user-space identity.
The repo ships the known-good mapping at
`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt`. Use `platform:macOS`
for SDL3 consumers such as current PCSX2 builds; older `platform:Mac OS X`
mapping lines can be ignored by SDL 3.2.x.

For PCSX2, use SDL macOS Compatibility with user-space-only output.
The SDL mapping targets the user-space PID `0x4448`, not the DriverKit PID `0x4447`.
Do not spoof an SDL-known third-party controller VID/PID for this path: on macOS,
GameController.framework can claim those identities before SDL's IOKit backend
can enumerate them. The custom OJD PID plus explicit SDL mapping is intentional.
Xbox 360 compatibility is exposed as an experimental user-space HID identity
using Microsoft's XUSB-to-DirectInput HID mapping. It is descriptor-backed, but
it is not true Windows XInput/XUSB emulation: macOS cannot publish XUSB device
interfaces or XInput IOCTLs through IOHIDUserDevice. The DirectInput-style
surface has combined triggers, hat-only D-pad, and no Guide/vibration/headset
semantics, so validate it per app.

If PCSX2's bundled SDL database does not include the OJD mapping, launch PCSX2
with the repo mapping override:

```bash
./scripts/ojd launch pcsx2
```

This sets `SDL_GAMECONTROLLERCONFIG` and `SDL_GAMECONTROLLERCONFIG_FILE` for
PCSX2 without modifying the signed app bundle. It also sets the installed daemon
to the known-good PCSX2 routing (`compat sdl-macos`, `output secondary`) before launch.
For normal PCSX2 launches, install the merged user-data SDL database and the
stale-index-tolerant input profile:

```bash
./scripts/ojd install pcsx2-sdl-db
./scripts/ojd install pcsx2-profile
```

PCSX2 checks `~/Library/Application Support/PCSX2/game_controller_db.txt` before
its bundled resources. The `OpenJoystickDriver` input profile binds both `SDL-0`
and `SDL-1` so it still works while an old DriverKit device occupies one SDL slot.
`scripts/ojd-install-pcsx2-mapping.sh` can append the mapping to PCSX2's bundled
database when macOS allows app-bundle writes, but recent macOS builds may block
that even with administrator rights.

Each connected controller runs through an isolated `DevicePipeline` actor. The
daemon exposes XPC status/control APIs to the GUI and CLI. The GUI is not the
driver owner; the daemon can run without the menu bar app open.

## LLM and Agent Context

This repo includes dedicated context files for coding agents and LLM tooling:

- [AGENTS.md](AGENTS.md) - working instructions for repo agents
- [llms.txt](llms.txt) - concise project map
- [llms-full.txt](llms-full.txt) - expanded architecture, validation, and device context

`CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md` are symlinks to
`AGENTS.md`. Edit `AGENTS.md`; the other instruction surfaces follow it.

## Star History

<a href="https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&logscale=&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&theme=dark&logscale&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&logscale&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&logscale&legend=top-left" />
 </picture>
</a>

## License

[MIT](LICENSE)
