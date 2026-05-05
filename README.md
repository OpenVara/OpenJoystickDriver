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
DriverKit HID backend       -> system extension virtual HID device
IOHIDUserDevice backend     -> userspace compatibility virtual controller
```

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
