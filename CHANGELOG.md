# Changelog

All notable changes to OpenJoystickDriver are documented in this file.

## 0.4.0

### Added

- Added regression coverage for stale active input across parser release events,
  compatibility route handoff, virtual HID neutral reports, and pipeline stop.

### Changed

- Refined the menu-bar and Input Test UI for clearer permissions, game profile,
  live input, packet log, and rumble workflows.
- Added right-click menu-bar fallback behavior so right-click opens the popover.

### Fixed

- Neutralized forwarded virtual output when a controller pipeline stops or a USB
  input loop exits, preventing stale held buttons after disconnect or teardown.
- Fixed Xbox 360 HID compatibility reports so SDL HIDAPI receives the expected
  state packet header, preventing intermittent LB/RB latch/stuck-active states.

## 0.3.1

### Fixed

- Fixed Xbox 360 HID compatibility reports so SDL HIDAPI receives the expected
  state packet header, preventing intermittent LB/RB latch/stuck-active states.

## 0.3.0

### Added

- Added focused Compatibility routing with dedicated per-consumer user-space
  routes for simultaneous SDL apps such as PCSX2 and DuckStation.
- Added per-controller idle sleep gating that neutralizes forwarded state and
  stops keep-alive traffic while a controller is idle.
- Added focused foreground-routing and sleep-gate regression coverage while
  migrating the test suite to Swift Testing.

### Fixed

- Fixed focused-app handoff so simultaneous SDL consumers no longer hijack each
  other's active controller route.
- Fixed a foreground-consumer misclassification that could freeze controller
  input for a few seconds mid-game.

## 0.2.0

### Added

- Added stock SDL HIDAPI-compatible Xbox 360 rumble path for PCSX2 and SDL apps.
- Added release automation for app bundle versions and drag-and-drop DMG packaging.

### Changed

- Switched release packaging from zip-only distribution to a standard macOS DMG.

## 0.1.0-rc.2

### Added

- Added hardware-confirmed DualShock 4 Bluetooth input support through Sony HID
  report `0x11`.
- Added DualShock 4 Bluetooth physical rumble support through output report
  `0x11` with CRC framing.
- Added IOHID transport/report ID propagation so Bluetooth DS4 devices select
  the Sony Bluetooth report path.
- Added regression coverage for observed macOS Bluetooth DS4 report bytes.

### Changed

- Updated compatibility docs and LLM context to distinguish DualShock 4
  Bluetooth support from unsupported non-DS4 Bluetooth controllers.

## 0.1.0-rc.1

### Added

- Added DualShock 4 USB input support with raw HID-normalized stick values.
- Added DualShock 4 physical rumble over HID output report `0x05`.
- Added app-rumble forwarding for Compatibility devices through supported Xbox
  One, Xbox 360, and compact OJD rumble reports.
- Added Input Test controls for live input, packet logs, physical rumble, and
  controller-specific button glyphs.
- Added user-space compatibility identities for SDL 2/3, Apple GameController,
  Generic HID, Xbox 360 HID, and Xbox One HID.
- Added RTK filter install command plumbing under `./scripts/ojd rtk`.

### Changed

- Reworked the menu-bar app so OpenJoystickDriver stays menu-bar-only and keeps
  the status item alive reliably.
- Improved the Input Test window sizing, layout, button grid, and rumble control
  labels.
- Updated README into a shorter user-first guide.
- Moved detailed compatibility information into an emoji-based feature matrix in
  `docs/COMPATIBILITY_LAYERS.md`.
- Clarified Sony controller names: DualShock 4 is supported over USB; DualShock
  3 and DualSense are not implemented.

### Fixed

- Fixed D-pad state tracking so held D-pad directions appear in Input Test state.
- Fixed a daemon/user-space output dispatcher race when creating virtual devices.
- Fixed app rumble parsing so unmarked DriverKit relay bytes are not treated as
  rumble commands.
- Fixed the app delegate lifetime so the menu-bar app can launch and remain
  visible.
