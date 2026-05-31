# AGENTS.md

OpenJoystickDriver is a macOS menu-bar app + daemon that publishes virtual gamepads.

Treat the user request as the task; preserve existing behavior. Work from repo evidence; you must not claim support unless code, tests, or hardware notes prove it.

**Source of truth:**

- Controller profiles: `Sources/OpenJoystickDriverKit/Resources/Controllers/*.json` (decimal numbers; no local `$schema`)
- GIP device schemas: `Resources/Schemas/Devices/*.json`
- Scripts: `./scripts/ojd`

Validate changes with `rtk ./scripts/ojd validate profiles` and `rtk test swift test`.

Full instructions: `docs/AGENTS_FULL.md`.
