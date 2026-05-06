# OpenJoystickDriver macOS 10.15 Test Kit

Use this on the macOS 10.15 machine after unpacking
`OpenJoystickDriver-10.15-dev-testkit.zip`.

## Read-only smoke check

```bash
./scripts/ojd-catalina-smoke.sh ./OpenJoystickDriver.app
```

## LaunchAgent registration check

Copy the app to `/Applications`, then run:

```bash
cp -R ./OpenJoystickDriver.app /Applications/OpenJoystickDriver.app
./scripts/ojd-catalina-smoke.sh /Applications/OpenJoystickDriver.app --install
```

The script reports the app bundle minimum OS, binary architectures, x86_64
minimum OS load commands, icon resource, bundled LaunchAgent plist, headless
status output, and optional `launchctl` registration result.
