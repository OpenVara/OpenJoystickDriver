# Compatibility Layers

OpenJoystickDriver has five user-space compatibility identities. Use this file
for consumer-visible button and axis mappings; keep `README.md` focused on setup
and common workflows.

## Browser Gamepad API Mappings

## Choosing A Compatibility Identity

The switch is the Compatibility identity picker in the app, or the
`OpenJoystickDriver --headless compat ...` command in CLI mode. OJD publishes
one user-space compatibility identity at a time:

| Consumer                                   | Use                                                |
| ------------------------------------------ | -------------------------------------------------- |
| PCSX2, Steam, DuckStation, SDL apps        | `sdl2-3`                                           |
| Native macOS GameController.framework apps | `apple-gamecontroller`                             |
| Browser Gamepad API and direct HID readers | `generic-hid` or the active compatibility identity |
| Hardware-spoof experiments                 | `x360-hid` or `xone-hid`                           |

## Application Rumble

Compatibility devices now register an `IOHIDUserDevice` set-report callback.
When an app writes a supported HID output report, OJD converts it into the
physical controller rumble path already used by the built-in rumble tester.

Supported app-facing report shapes:

- Xbox One haptics output report ID `3`.
- Xbox 360 rumble packets such as `[0x00, 0x08, 0x00, left, right, 0, 0, 0]`.
- OJD compact rumble packets `[0x4F, left, right, lt, rt, durationLo, durationHi]`.

The bridge requires a connected physical controller whose parser implements
`PhysicalRumbleOutput`. GIP/Xbox controllers support it; parsers without physical
rumble support still accept input but ignore app rumble.

### SDL 2/3 Compatibility (`sdl2-3`)

Use this for SDL consumers such as PCSX2, Steam, DuckStation, and Parsec host
routing. It uses the OJD-owned VID/PID and the SDL mapping in
`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt`.

| Browser control | Meaning     |
| --------------- | ----------- |
| `B0`            | A           |
| `B1`            | B           |
| `B2`            | X           |
| `B3`            | Y           |
| `B4`            | LB          |
| `B5`            | RB          |
| `B6`            | L3          |
| `B7`            | R3          |
| `B8`            | RCB / Menu  |
| `B9`            | LCB / View  |
| `B10`           | Xbox/Home   |
| `B11`           | D-pad Up    |
| `B12`           | D-pad Down  |
| `B13`           | D-pad Left  |
| `B14`           | D-pad Right |
| `B15`           | BCB / Share |

Axes use `A0`/`A1` for left stick, `A2` for LT, `A3`/`A4` for right stick,
and `A5` for RT. LT and RT idle at zero and move independently. D-pad is
button-backed only.

### Generic HID (`generic-hid`)

Use this for descriptor-driven apps that should not receive a spoofed Microsoft
VID/PID. Its Browser Gamepad API mapping is the same button order as `sdl2-3`:

| Browser control | Meaning     |
| --------------- | ----------- |
| `B0`            | A           |
| `B1`            | B           |
| `B2`            | X           |
| `B3`            | Y           |
| `B4`            | LB          |
| `B5`            | RB          |
| `B6`            | L3          |
| `B7`            | R3          |
| `B8`            | Menu        |
| `B9`            | View        |
| `B10`           | Xbox/Home   |
| `B11`           | D-pad Up    |
| `B12`           | D-pad Down  |
| `B13`           | D-pad Left  |
| `B14`           | D-pad Right |
| `B15`           | Share       |

Axes use `A0`/`A1` for left stick, `A2` for LT, `A3`/`A4` for right stick,
and `A5` for RT. LT and RT idle at zero and move independently. D-pad is
button-backed only.

### Apple GameController (`apple-gamecontroller`)

Use this for native macOS apps that consume controllers through Apple's
GameController.framework. It publishes the Xbox 360 HID-compatible report shape
that `GCController.supportsHIDDevice(_:)` accepts as a native `GCController`.

Its consumer-visible controls match the Xbox compatibility table below.

### Xbox 360 HID (`x360-hid`) and Xbox One HID (`xone-hid`)

These are experimental Microsoft hardware-spoof identities. Browser Gamepad API
maps them like an Xbox controller compatibility surface:

| Browser control | Meaning     |
| --------------- | ----------- |
| `B0`            | A           |
| `B1`            | B           |
| `B2`            | X           |
| `B3`            | Y           |
| `B4`            | LB          |
| `B5`            | RB          |
| `B6`            | LT          |
| `B7`            | RT          |
| `B8`            | View        |
| `B9`            | Menu        |
| `B10`           | L3          |
| `B11`           | R3          |
| `B12`           | D-pad Up    |
| `B13`           | D-pad Down  |
| `B14`           | D-pad Left  |
| `B15`           | D-pad Right |
| `B16`           | Xbox/Home   |

## SDL Mapping

`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt` maps `sdl2-3` as:

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

## Manual Audit

Before treating mapping changes as end-to-end verified, check:

1. Browser Gamepad API for the selected compatibility identity against the
   relevant table above.
2. SDL2/3 with `sdl2-3`: idle `A2` and `A5` are zero, D-pad is four buttons,
   and D-pad release clears all four button states.
3. DuckStation and PCSX2 with `sdl2-3`: face buttons, View/Menu, L3/R3, D-pad,
   and analog triggers bind once and do not create repeated up/down input.
4. Parsec macOS to Windows with `sdl2-3`: Persona 5 receives stable D-pad input
   and A/B/X/Y match the host-side SDL mapping.
