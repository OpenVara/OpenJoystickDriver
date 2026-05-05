# OpenJoystickDriver Architecture

OpenJoystickDriver is a daemon-owned controller pipeline. The GUI and CLI are
clients of the daemon; they do not own input capture, physical-controller output,
or virtual-controller publication.

## Runtime Boundaries

```text
Physical USB/HID device
  -> DeviceManager
  -> one DevicePipeline actor per controller
  -> protocol parser and optional protocol output capabilities
  -> virtual output dispatcher
  -> DriverKit relay or IOHIDUserDevice profile
```

The pipeline boundary is per controller. One device failing to parse, reconnect,
or send output should not take down another connected controller.

## Controller Profiles

Controller metadata is profile-driven. Bundled controller profiles live in:

```text
Sources/OpenJoystickDriverKit/Resources/Controllers/
```

Device schemas live in:

```text
Resources/Schemas/Devices/
```

The runtime catalog loads controller profiles directly. The old monolithic
device catalog shape is not a supported runtime input. New devices should add
one controller profile plus, for GIP devices, a matching device schema.

Device-specific USB behavior belongs in data:

- endpoint addresses
- `setConfiguration(1)` before claim
- post-handshake settle delay
- protocol variant
- mapping flags
- preferred virtual output backends

Parser code should only carry behavior required by a protocol family.

## Protocol Extensions

Input parsers convert raw reports into `ControllerEvent` values. Optional
physical-controller output is modeled as explicit protocol capabilities, not as
special cases in `DevicePipeline`.

Current capability surface:

- `PhysicalRumbleOutput`: source-controller rumble with `L`, `R`, `LT`, and `RT`
  byte values in the `0...255` range.

Current source-backed physical rumble implementations:

- GIP Xbox One / Series class controllers
- Xbox 360 wired controllers

If a protocol has no verified physical output path, it must not expose a live
control in the app.

## Virtual Output

DriverKit and IOHIDUserDevice are separate output surfaces:

```text
DriverKit HID backend    -> private relay and fallback diagnostics
IOHIDUserDevice backend  -> consumer-facing user-space profiles
```

User-space compatibility profiles are first-class profiles, not hidden parser
quirks:

- `sdl-macos`: OJD-owned SDL/Steam/PCSX2 identity with explicit SDL mapping
- `generic-hid`: OJD-owned descriptor-driven HID gamepad
- `x360-hid`: experimental Xbox 360 HID hardware-spoof profile
- `xone-hid`: experimental Xbox One HID hardware-spoof profile

The Microsoft-spoof profiles are HID compatibility surfaces. They are not
Windows XInput or XUSB emulation on macOS.

## Extension Rules

To add a controller:

1. Add a controller profile under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.
2. Add a matching `Resources/Schemas/Devices/*.json` file for GIP devices.
3. Keep protocol quirks in `protocol.variant`, `protocol.mapping_flags`, and
   transport data unless parser behavior truly changes.
4. Add parser tests or report-format tests for any new protocol behavior.
5. Validate with `./scripts/ojd validate profiles` and `swift test`.

To add a protocol:

1. Add a parser under `Sources/OpenJoystickDriverKit/Protocol/`.
2. Add any optional physical output capability under
   `Sources/OpenJoystickDriverKit/Protocol/Capabilities/`.
3. Register the parser in `ParserRegistry`.
4. Add controller profile schema support before adding device profiles that use
   the protocol.

To add a virtual output profile:

1. Add the `VirtualDeviceProfile`.
2. Add or update the HID descriptor/report format under
   `Sources/OpenJoystickDriverKit/Output/HID/`.
3. Add a `CompatibilityOutputProfile` entry only when it is a user-selectable
   compatibility surface.
4. Add a consumer mapping file when SDL or another consumer requires one.

## Validation Contract

Source-level validation:

```bash
swift test
./scripts/ojd validate profiles
```

Runtime validation for backend changes:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
```

DriverKit approval, TCC permissions, physical rumble, and real controller input
remain hardware/runtime checks. CI cannot prove them end to end.
