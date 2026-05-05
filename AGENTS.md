# OpenJoystickDriver Agent Instructions

OpenJoystickDriver is a macOS userspace gamepad driver. Keep changes grounded in
current source, controller profile schemas, and observed hardware behavior.

## Source of Truth

- Runtime profiles: `Sources/OpenJoystickDriverKit/Resources/Controllers/*.json`
- Device schemas: `Resources/Schemas/Devices/*.json`
- JSON schemas: `Resources/Schemas/*.schema.json`
- Build/signing scripts: `scripts/ojd` and `scripts/ojd-*.sh`
- Swift package graph: `Package.swift`
- DriverKit project: `OpenJoystickVirtualHIDDevice/`

Do not document behavior as supported unless production code, schemas, tests, or
manual hardware notes in this repo support it.

## Current Hardware Notes

- GameSir G7 SE is hardware verified for GIP input and Xbox One HID
  compatibility mode.
- Flydigi Vader 5S is supported through the GIP path and needs
  `setConfiguration(1)` before claim plus a post-handshake settle delay.
- DualShock 4 USB parser support exists, but this repo does not currently have
  local hardware verification for it.
- Bluetooth, DualSense, and Switch Pro support are not implemented.

## Edit Rules

- Keep local `$schema` references out of committed JSON. Use
  `https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/...`.
- Add one controller profile per device under
  `Sources/OpenJoystickDriverKit/Resources/Controllers/`.
- Add a matching `Resources/Schemas/Devices/*.json` file for GIP controllers.
- Use decimal VID, PID, endpoint, and packet values in JSON files.
- Keep protocol variants and mapping flags in data where possible; do not bake
  device quirks into parser code unless the protocol requires it.
- Avoid broad rewrites of signing, DriverKit, or daemon lifecycle code without
  targeted validation.

## Validation

Run focused checks for the touched surface:

```bash
./scripts/ojd validate profiles
swift test
bash -n scripts/ojd scripts/ojd-*.sh
```

For backend/runtime changes, also use the relevant diagnostics:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
```

DriverKit, signing, notarization, TCC permissions, and real controller input may
require local macOS hardware validation. CI cannot prove those end to end.

## Known Runtime Caveat

Compatibility mode can still create a stale, non-working first controller
instance in browser Gamepad API pages. Treat that as a runtime/backend issue,
not as evidence that the controller profile mapping is wrong.

## Documentation Surfaces

- `README.md` is the human entry point.
- `llms.txt` is concise LLM context.
- `llms-full.txt` is expanded LLM context.
- `CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md` should remain
  symlinks to this file.
