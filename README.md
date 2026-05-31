# OpenJoystickDriver

OpenJoystickDriver is a macOS menu-bar app and daemon that turns supported
physical controllers into app-friendly virtual controllers.

Use it when a controller works in OJD but not in a game, emulator, browser, SDL
app, or native macOS app.

<img width="512" height="632" alt="image" src="https://github.com/user-attachments/assets/b2ad4741-8082-445f-8721-d66edb3f79df" />


## Status

| Item | Status | Notes |
| --- | --- | --- |
| GameSir G7 SE | ✅ | Hardware verified through GIP and Xbox One HID compatibility. |
| Flydigi Vader 5S | ✅ | Uses GIP and needs `setConfiguration(1)` before claim. |
| Sony DualShock 4 (USB/Bluetooth) | ✅ | Input and physical rumble are implemented. |
| Xbox 360 wired (USB) | ✅ | Parser and profiles exist; hardware coverage varies by model. |
| More xpad-derived Xbox batches | 🚧 | Profiles exist but need local hardware checks. |
| DualShock 3 / DualSense / Switch Pro | ❌ | Not implemented. |

For the full feature matrix, mapping notes, and per-mode caveats, see
[docs/COMPATIBILITY_LAYERS.md](docs/COMPATIBILITY_LAYERS.md).

## Quickstart (Using The App)

1. Install `OpenJoystickDriver.app` into `/Applications`.
2. Open the menu-bar item.
3. Follow the UI prompts to grant **Input Monitoring** for the app and helper.
4. Connect a supported controller.
5. Use **Input Test** to confirm buttons/sticks and physical rumble.

## Choose An Output Mode

| What you are trying to run | Recommended | Why |
| --- | --- | --- |
| Most games, Steam, emulators, SDL apps | Compatibility + `SDL 2/3` | Stable app-facing identity and mapping. |
| Native macOS apps using `GCController` | Compatibility + `Apple GameController` | Targets GameController.framework consumers. |
| Apps that inspect HID descriptors | Compatibility + `Generic HID` | Descriptor-driven HID surface. |
| A picky app expecting Microsoft HID | Compatibility + `Xbox 360 HID` or `Xbox One HID` | Experimental spoof identities for targeted testing. |

CLI equivalents (installed app bundle):

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless output secondary
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Menu UI says “running (disconnected)” | Use **Restart Helper** in the menu, or run `--headless restart`. |
| SDL / browser sees 0 controllers | Ensure Input Monitoring is granted, then re-open the app and re-test. |
| DriverKit extension install fails | Compatibility mode still works without DriverKit. Use DriverKit only when you need it. |

Useful commands:

```bash
./scripts/ojd validate profiles
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
swift test
```

From the installed app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
```

## Development

If you're changing parsers/profiles/tests, signing is not required:

```bash
brew install libusb
swift test
```

If you're working on the app/daemon, DriverKit, or signing/notarization, start here:

- [scripts/README.md](scripts/README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
