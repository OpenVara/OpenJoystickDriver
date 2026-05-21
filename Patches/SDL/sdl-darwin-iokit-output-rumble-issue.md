# macOS IOKit backend: virtual HID gamepad input works, but rumble is not sent

I am testing a macOS virtual HID gamepad made by OpenJoystickDriver. Input works in SDL apps, but rumble does not work in PCSX2 unless SDL is patched to send a HID output report.

This is only a bug report / design note, not a code contribution. I read SDL's AI rules. The investigation used an AI coding agent, so I am not submitting the generated test patch as SDL code.

## Setup

- macOS 26.5, build 25F71, Apple Silicon
- PCSX2 v2.6.3, x86_64
- PCSX2 bundle id: `net.pcsx2.pcsx2`
- PCSX2 bundled SDL: `Contents/Frameworks/libSDL3.0.dylib`
- The bundled SDL is x86_64 and reports current dylib version `201.26.0`

Controller:

- GameSir G7 SE
- VID/PID: `3537:1010`
- OpenJoystickDriver handles it as a GIP controller
- OJD then exposes a virtual `IOHIDUserDevice` gamepad for SDL/apps

Game test:

- Midnight Club 3: DUB Edition in PCSX2
- In that game, pressing RT for nitrous should rumble the controller if the car has nitrous

## What happens

With stock PCSX2 / stock bundled SDL:

- the virtual gamepad shows up
- game input works
- RT works for nitrous
- no rumble happens

With the same PCSX2 app, but its bundled SDL replaced in a copied test app with a locally patched SDL build:

- input still works
- RT/nitrous still works
- rumble works when nitrous is used

The copied app was `/private/tmp/PCSX2-OJD.app`, re-signed locally after replacing SDL. The real `/Applications/PCSX2.app` was not modified.

The patched SDL build was based on SDL `release-3.4.8` / commit `d9d553670`.

## What I think is happening

OJD's virtual gamepad can receive HID output reports. Its `IOHIDUserDevice` set-report callback receives output reports and can forward rumble to the real controller.

The problem seems to be earlier in the chain: PCSX2 calls `SDL_RumbleGamepad()`, but SDL's macOS IOKit backend only treats the device as rumble-capable if there is an Apple ForceFeedback service.

This virtual HID device is not a ForceFeedback device. It is a normal HID gamepad with an output report. So SDL never sends the rumble report.

## Possible direction

I think there are two separate pieces here:

1. SDL's Darwin/IOKit backend could support `SDL_SendJoystickEffect()` by sending raw HID output reports with `IOHIDDeviceSetReport()`.
2. `SDL_RumbleGamepad()` still needs a known mapping from low/high rumble values to a device's output report format. SDL probably should not assume every HID output report means rumble.

So a possible fix would be:

- keep the existing ForceFeedback path when ForceFeedback exists;
- add a generic IOKit output-report helper for `SDL_SendJoystickEffect()`;
- only expose `SDL_RumbleGamepad()` for non-ForceFeedback HID devices when SDL knows that device/protocol's rumble output report format.

This would help virtual HID gamepads that support rumble through output reports but do not have Apple's ForceFeedback service.
