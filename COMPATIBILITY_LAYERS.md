# Compatibility Layers

This page lists what each OJD output mode is for. README stays short; detailed
mapping and caveats live here.

## Legend

| Mark  | Meaning                                           |
| ----- | ------------------------------------------------- |
| ✅     | Works now                                         |
| ⚠️     | Works, but has a caveat                           |
| 🚧     | Under construction or needs more hardware testing |
| ❌     | Not implemented                                   |
| `N/A` | Not part of that mode                             |

## Feature Set

| Feature                          | Status | Best mode                          | Notes                                                                                                  |
| -------------------------------- | ------ | ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Menu-bar app                     | ✅      | `N/A`                              | OJD is menu-bar-only.                                                                                  |
| Input Test window                | ✅      | `N/A`                              | Shows live input, packets, and physical rumble controls.                                               |
| GameSir G7 SE                    | ✅      | `sdl2-3` or `xone-hid`             | Hardware verified through GIP and Xbox One HID compatibility.                                          |
| Flydigi Vader 5S                 | ✅      | `sdl2-3`                           | Uses GIP and needs `setConfiguration(1)` before claim.                                                 |
| Sony DualShock 4 USB input       | ✅      | `sdl2-3` or `apple-gamecontroller` | USB HID parser is implemented.                                                                         |
| Sony DualShock 4 Bluetooth input | ✅      | `sdl2-3` or `apple-gamecontroller` | Bluetooth HID report `0x11` parser support is implemented.                                             |
| Sony DualShock 4 physical rumble | ✅      | Compatibility modes                | USB and Bluetooth output reports are implemented. App rumble routes through compatibility set reports. |
| Xbox 360 USB parser              | ✅      | `sdl2-3` or `x360-hid`             | Parser and profiles exist. Hardware coverage varies by model.                                          |
| xpad-derived Xbox batches        | 🚧      | Varies                             | Added from source data, not all locally hardware verified.                                             |
| Generic USB HID fallback         | ⚠️      | `generic-hid`                      | Basic fallback for descriptor-driven apps.                                                             |
| SDL 2/3 apps                     | ✅      | `sdl2-3`                           | Use for Steam, PCSX2, DuckStation, Moonlight/SDL, and similar apps.                                    |
| Apple GameController apps        | ✅      | `apple-gamecontroller`             | Use for native macOS apps that read `GCController`.                                                    |
| Browser Gamepad API              | ⚠️      | active compatibility identity      | Browser mappings can vary by identity and stale devices.                                               |
| App rumble                       | ✅      | Compatibility modes                | Parses Xbox One, Xbox 360, and compact OJD rumble reports.                                             |
| DriverKit output                 | ⚠️      | `driverKit`                        | Good for relay/diagnostics; not the main app compatibility path.                                       |
| Other Bluetooth controllers      | ❌      | `N/A`                              | Not implemented.                                                                                       |
| Sony DualShock 3                 | ❌      | `N/A`                              | Not implemented; no local physical device is available for testing.                                    |
| Sony DualSense                   | ❌      | `N/A`                              | Not implemented. This is the PS5 controller family.                                                    |
| Switch Pro                       | ❌      | `N/A`                              | Not implemented.                                                                                       |

## Pick A Mode

| User goal                                       | Choose                   | Why                                                               |
| ----------------------------------------------- | ------------------------ | ----------------------------------------------------------------- |
| Most games and emulators                        | ✅ `sdl2-3`               | Best default for SDL-based apps.                                  |
| Native macOS app using GameController.framework | ✅ `apple-gamecontroller` | Publishes a `GCController`-friendly Xbox-style HID surface with haptics. |
| SDL app needs output-report rumble              | 🚧 `x360-hid`             | Test with `./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5`.  |
| SDL app needs macOS GameController rumble       | 🚧 `apple-gamecontroller` | GameController haptics work; SDL MFI enumeration is still gated.  |
| Direct HID testing                              | ⚠️ `generic-hid`          | Keeps OJD's own VID/PID and exposes a plain HID GamePad.          |
| App expects Xbox 360 HID                        | 🚧 `x360-hid`             | Experimental Microsoft-style HID identity.                        |
| App expects Xbox One HID                        | 🚧 `xone-hid`             | Experimental Microsoft-style HID identity.                        |
| DualShock 4 over Bluetooth                      | ✅ `sdl2-3`               | Uses Sony Bluetooth HID report parsing with compatibility output. |

CLI examples:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat apple-gamecontroller
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless output secondary
./scripts/ojd diagnose sdl3-gamecontroller --seconds 5
./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5
```

## App Rumble

OJD can forward app rumble to the physical controller when both sides support it.

| App-facing report                                                        | Status | Physical target                                          |
| ------------------------------------------------------------------------ | ------ | -------------------------------------------------------- |
| Xbox One output report ID `3`                                            | ✅      | GIP/Xbox and DualShock 4-compatible physical rumble path |
| Xbox 360 packet `[0x00, 0x08, 0x00, left, right, 0, 0, 0]`               | ✅      | Main left/right motors                                   |
| OJD compact packet `[0x4F, left, right, lt, rt, durationLo, durationHi]` | ✅      | Main and trigger motors when present                     |
| DualShock 4 Bluetooth output report `0x11`                               | ✅      | Main left/right motors                                   |

Notes:

- Sony DualShock 4 has two physical motors. OJD ignores trigger motor values for DualShock 4.
- GIP/Xbox controllers can use main motors and trigger motors when the physical
  protocol exposes them.
- DriverKit relay bytes are ignored unless they match a supported rumble report.

## Browser Mapping

### `sdl2-3` and `generic-hid`

| Browser control               | Meaning                        |
| ----------------------------- | ------------------------------ |
| `B0` / `B1` / `B2` / `B3`     | A / B / X / Y                  |
| `B4` / `B5`                   | LB / RB                        |
| `B6` / `B7`                   | L3 / R3                        |
| `B8` / `B9`                   | Menu / View                    |
| `B10`                         | Xbox/Home                      |
| `B11` / `B12` / `B13` / `B14` | D-pad Up / Down / Left / Right |
| `B15`                         | Share                          |
| `A0` / `A1`                   | Left stick X / Y               |
| `A2`                          | LT                             |
| `A3` / `A4`                   | Right stick X / Y              |
| `A5`                          | RT                             |

LT and RT idle at zero. D-pad is button-backed only.

### `apple-gamecontroller`, `x360-hid`, and `xone-hid`

| Browser control               | Meaning                        |
| ----------------------------- | ------------------------------ |
| `B0` / `B1` / `B2` / `B3`     | A / B / X / Y                  |
| `B4` / `B5`                   | LB / RB                        |
| `B6` / `B7`                   | LT / RT                        |
| `B8` / `B9`                   | View / Menu                    |
| `B10` / `B11`                 | L3 / R3                        |
| `B12` / `B13` / `B14` / `B15` | D-pad Up / Down / Left / Right |
| `B16`                         | Xbox/Home                      |

## SDL Mapping

`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt` maps `sdl2-3` like this:

| SDL control                              | HID source                    |
| ---------------------------------------- | ----------------------------- |
| `a` / `b` / `x` / `y`                    | `b0` / `b1` / `b2` / `b3`     |
| `leftshoulder` / `rightshoulder`         | `b4` / `b5`                   |
| `leftstick` / `rightstick`               | `b6` / `b7`                   |
| `start` / `back` / `guide`               | `b8` / `b9` / `b10`           |
| `dpup` / `dpdown` / `dpleft` / `dpright` | `b11` / `b12` / `b13` / `b14` |
| `misc1`                                  | `b15`                         |
| `leftx` / `lefty`                        | `a0` / `a1`                   |
| `lefttrigger`                            | `a2`                          |
| `rightx` / `righty`                      | `a3` / `a4`                   |
| `righttrigger`                           | `a5`                          |

## PCSX2

Use `sdl2-3` with user-space-only output:

```bash
./scripts/ojd install pcsx2-sdl-db
./scripts/ojd install pcsx2-profile
./scripts/ojd launch pcsx2
```

PCSX2 reads this user data file before its bundled database:

```text
~/Library/Application Support/PCSX2/game_controller_db.txt
```

The included input profile binds the single expected `SDL-0` OJD Compatibility
controller.

For SDL apps that need rumble through macOS GameController haptics, use:

```bash
./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5
./scripts/ojd launch pcsx2 --hidapi-rumble
```

That route selects `x360-hid`, enables user-space output, and launches SDL with
Xbox 360 HIDAPI enabled for the Steam Virtual Gamepad-style identity. SDL's
GameController/MFI route remains available for diagnostics, but current SDL3
builds have not enumerated OJD through that path in local testing.

## Manual Checks

Before calling a mapping fully verified, check the exact app and mode:

1. Browser Gamepad API: buttons and axes match the active identity table.
2. SDL 2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
3. PCSX2 or DuckStation: face buttons, View/Menu, L3/R3, D-pad, and triggers bind once.
4. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
5. Rumble: app output report reaches the physical controller if the controller supports rumble.
