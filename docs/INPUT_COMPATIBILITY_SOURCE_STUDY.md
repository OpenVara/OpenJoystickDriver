# Input Compatibility Source Study

Internal design note: this maps external controller-compatibility projects into
concrete OpenJoystickDriver (OJD) architecture decisions. It does not imply
support, endorsement, or platform coverage for those projects.

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
OJD-owned identity and mapping database. OJD must not try to solve every app by
spoofing Xbox HID. Many consumers already trust SDL's canonical gamepad
abstraction; OJD must feed that path cleanly.

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
profile split match this shape.

### xinput-gui

xinput-gui is not a gamepad translation layer. It wraps Linux Xorg `xinput`
commands to list devices, list properties, set properties, float devices, and
reattach devices to master devices.

Decision for OJD: its useful lesson is operational, not protocol-level. OJD
must expose diagnostics and device/control-plane state clearly, but this note
must not be used to justify macOS HID or GameController behavior changes.

### DualShock4-emulator

DualShock4-emulator maps XInput, keyboard, mouse, and optional motion input into
a virtual DS4 target through ViGEm. The mapping includes Xbox face buttons to
DS4 Cross/Circle/Square/Triangle, trigger analog values plus DS4 trigger button
bits, hat-based d-pad directions including diagonals, Share/touchpad swapping,
touchpad coordinates, motion, and rumble feedback forwarding to XInput.

Decision for OJD: DS4 cannot be treated as "just another button layout." A real
DS4 output profile needs special state for hat encoding, special buttons,
touchpad, motion, lightbar/rumble feedback, and authentication/feature-report
behavior. Until that is implemented and hardware-verified, OJD must keep DS4
parser support separate from DS4 emulation support.

### Gopher360

Gopher360 consumes XInput and emits keyboard/mouse input with SendInput. It is a
consumer-side remapper for desktop control, not a virtual gamepad driver. It
assumes the input is already native XInput or has been translated into XInput by
another layer.

Decision for OJD: OJD must not mix gamepad output with keyboard/mouse injection in
the core controller pipeline. If OJD ever adds desktop-control mappings, they
must be a separate output backend and must be opt-in, because they can move
the macOS cursor or send system input while a game is focused.

### Joypad OS

Joypad OS has the closest architecture match. It normalizes transports and
controllers into `input_event_t`, including device type, transport, layout,
buttons, analog axes, hats, chatpad, rumble capability, motion, pressure,
touchpad, and battery data. It then routes that state through player management,
profiles, output targets, and output-specific descriptors/modes such as HID,
PS3, PS4, Switch, XInput, Xbox One, and original Xbox.

Decision for OJD: OJD must formalize its canonical input state as the long-term
contract between parser and output layers. Output identities must be data- or
profile-backed encoders that consume canonical state. App-specific compatibility
belongs in consumer profiles and launch/diagnostic tooling, not in parser code.

## OJD Architecture Decisions

1. OJD must keep the canonical-state boundary.
   Parsers normalize GIP, DS4, and generic HID into OJD state. Output backends
   encode that state into DriverKit HID, IOHIDUserDevice HID, SDL-friendly HID,
   Xbox HID profiles, or future DS4 profiles.

2. OJD must keep app compatibility separate from controller support.
   A controller profile proves how to read hardware. A consumer profile proves
   how an app stack should see OJD output. SDL apps, browser Gamepad API, SDL3
   probes, and GameController.framework must remain separate validation
   surfaces.

3. OJD must treat Apple GameController and Xbox hardware spoofing as explicit paths.
   `apple-gamecontroller` is for native GameController.framework consumers.
   `x360-hid` and `xone-hid` remain useful probes and may be useful for specific
   consumers. For SDL-based consumers, `sdl2-3` stays the recommended route.

4. OJD must treat DS4 output as a future protocol implementation, not a mapping rename.
   A DS4 backend needs report descriptors, special buttons, d-pad hat semantics,
   touchpad, motion, output reports, and compatibility tests before it can be
   documented as supported.

5. OJD must keep keyboard/mouse output isolated.
   Controller-to-keyboard/mouse behavior must never be implicit in the
   virtual gamepad path. It must be an explicit backend with focus and permission
   guardrails.

6. OJD must keep duplicate-device prevention as a first-class invariant.
   OJD must continue filtering its own virtual devices from input capture. Any
   new backend or identity must be covered by self-ingestion tests or diagnostic
   checks before it is exposed in normal mode.

## Concrete Follow-up Gates

These are future-work gates, not current support claims. Track concrete work in
issues/PRs instead of treating this list as a roadmap.

- Add a consumer-profile schema for SDL-based app stacks. It
  must describe preferred output identity, required SDL mappings, forbidden
  identities, launch environment, and diagnostics.
- Keep tests that assert `sdl2-3` and `generic-hid` expose D-pad through button
  bits and keep Share on the expected `misc1`/button path.
- Add a DS4-output design document before implementation. It must list feature
  reports, input report layout, output report layout, and what local hardware
  can verify.
- Keep `x360-hid` and `xone-hid` out of default launch flows until a clean
  rebooted host can run SDL3 probes and UI mapping without stuck enumeration.
