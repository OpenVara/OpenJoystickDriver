# Input Compatibility Source Study

This note maps the external controller compatibility projects inspected for
OpenJoystickDriver into concrete architecture decisions. It is not a support
claim for those projects or their target platforms.

## Source Set

- https://github.com/xan105/InputFusion
- https://github.com/emoose/Xb2XInput
- https://github.com/IvanFon/xinput-gui
- https://github.com/r57zone/DualShock4-emulator
- https://github.com/Tylemagne/Gopher360
- https://github.com/joypad-ai/joypad-os

All source evidence below came from shallow local clones on 2026-05-05.

## Evidence Map

### InputFusion

InputFusion is an app-facing API translation layer, not a kernel or HID driver.
Its XInput shim reads SDL3 gamepads and translates them to XInput state:
`SDL_GAMEPAD_BUTTON_SOUTH` to `XINPUT_GAMEPAD_A`, d-pad buttons to XInput d-pad
bits, SDL axes to XInput stick and trigger ranges, and rumble back through SDL.
It also deliberately removes the Guide bit from `XInputGetState` while keeping
`XInputGetStateEx` available.

Decision for OJD: keep SDL as a consumer compatibility target with a stable
OJD-owned identity and mapping database. Do not try to solve every app by
spoofing Xbox HID. The important lesson is that many consumers already trust
SDL's canonical gamepad abstraction; OJD should feed that path cleanly.

### Xb2XInput

Xb2XInput is a user-mode USB input to virtual XInput bridge. It enumerates known
USB VID/PID pairs, opens the controller with libusb, locates interrupt or bulk
endpoints, claims the interface, converts original Xbox input reports to
`XUSB_REPORT`, applies deadzones/remapping/Guide combinations, then updates a
ViGEm X360 target. It also relays ViGEm rumble notifications back to the source
controller through HID output reports.

Decision for OJD: the mature shape is input parser -> canonical state ->
backend-specific encoder -> feedback path. Device quirks belong in profiles and
parser code only when the protocol requires it. The OJD GIP path and output
profile split are aligned with this.

### xinput-gui

xinput-gui is not a gamepad translation layer. It wraps Linux Xorg `xinput`
commands to list devices, list properties, set properties, float devices, and
reattach devices to master devices.

Decision for OJD: its useful lesson is operational, not protocol-level. OJD
should expose diagnostics and device/control-plane state clearly, but this repo
does not justify any macOS HID or GameController behavior change.

### DualShock4-emulator

DualShock4-emulator maps XInput, keyboard, mouse, and optional motion input into
a virtual DS4 target through ViGEm. The mapping includes Xbox face buttons to
DS4 Cross/Circle/Square/Triangle, trigger analog values plus DS4 trigger button
bits, hat-based d-pad directions including diagonals, Share/touchpad swapping,
touchpad coordinates, motion, and rumble feedback forwarding to XInput.

Decision for OJD: DS4 cannot be treated as "just another button layout." A real
DS4 output profile needs special state for hat encoding, special buttons,
touchpad, motion, lightbar/rumble feedback, and authentication/feature-report
behavior. Until that is implemented and hardware-verified, OJD should keep DS4
parser support separate from DS4 emulation support.

### Gopher360

Gopher360 consumes XInput and emits keyboard/mouse input with SendInput. It is a
consumer-side remapper for desktop control, not a virtual gamepad driver. It
assumes the input is already native XInput or has been translated into XInput by
another layer.

Decision for OJD: do not mix gamepad output with keyboard/mouse injection in
the core controller pipeline. If OJD ever adds desktop-control mappings, they
should be a separate output backend and must be opt-in, because they can move
the macOS cursor or send system input while a game is focused.

### Joypad OS

Joypad OS has the closest architecture match. It normalizes transports and
controllers into `input_event_t`, including device type, transport, layout,
buttons, analog axes, hats, chatpad, rumble capability, motion, pressure,
touchpad, and battery data. It then routes that state through player management,
profiles, output targets, and output-specific descriptors/modes such as HID,
PS3, PS4, Switch, XInput, Xbox One, and original Xbox.

Decision for OJD: formalize OJD's canonical input state as the long-term
contract between parser and output layers. Output identities should be data- or
profile-backed encoders that consume canonical state. App-specific compatibility
belongs in consumer profiles and launch/diagnostic tooling, not in parser code.

## OJD Architecture Decisions

1. Keep the canonical-state boundary.
   Parsers normalize GIP, DS4, and generic HID into OJD state. Output backends
   encode that state into DriverKit HID, IOHIDUserDevice HID, SDL-friendly HID,
   Xbox HID profiles, or future DS4 profiles.

2. Keep app compatibility separate from controller support.
   A controller profile proves how to read hardware. A consumer profile proves
   how an app stack should see OJD output. PCSX2, Steam, browser Gamepad API,
   SDL3 probes, and GameController.framework should remain separate validation
   surfaces.

3. Treat Xbox hardware spoofing as explicit and narrow.
   `x360-hid` and `xone-hid` are useful probes and may be useful for specific
   consumers, but they are not the default long-term macOS answer. The current
   PCSX2/Rosetta wedging means `sdl-macos` stays the recommended route there.

4. Treat DS4 output as a future protocol implementation, not a mapping rename.
   A DS4 backend needs report descriptors, special buttons, d-pad hat semantics,
   touchpad, motion, output reports, and compatibility tests before it can be
   documented as supported.

5. Keep keyboard/mouse output isolated.
   Controller-to-keyboard/mouse behavior should never be implicit in the
   virtual gamepad path. It must be an explicit backend with focus and permission
   guardrails.

6. Keep duplicate-device prevention as a first-class invariant.
   OJD must continue filtering its own virtual devices from input capture. Any
   new backend or identity must be covered by self-ingestion tests or diagnostic
   checks before it is exposed in normal mode.

## Concrete Follow-up Gates

- Add a consumer-profile schema for app stacks such as PCSX2 and Steam. It
  should describe preferred output identity, required SDL mappings, forbidden
  identities, launch environment, and diagnostics.
- Add a PCSX2 stuck-state preflight before launching PCSX2 or Rosetta SDL
  probes. The script should refuse to run when `PCSX2` or `ojd-sdl3-probe`
  processes are stuck in `U` or `?E` state.
- Add tests that assert `sdl-macos` keeps hat d-pad mapping and Share on the
  expected SDL `misc1`/button path.
- Add a DS4-output design document before implementation. It must list feature
  reports, input report layout, output report layout, and what local hardware
  can verify.
- Keep `x360-hid` and `xone-hid` out of default PCSX2 launch flow until a clean
  rebooted host can run native SDL3, PCSX2/Rosetta SDL3, and PCSX2 UI mapping
  without stuck enumeration.
