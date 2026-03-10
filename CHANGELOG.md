# Changelog

All notable changes to OpenJoystickDriver are documented in this file.

## Unreleased

### Added

- **DriverKit virtual HID extension** — `OpenJoystickVirtualHIDDevice` (IOUserHIDDevice + user-client IPC) as the production output path for injecting gamepad input into the system HID stack
- **DextOutputDispatcher** — daemon-side output dispatcher that connects to the DriverKit extension via IOKit user-client
- **IOHIDVirtualOutputDispatcher** — fallback output path using `IOHIDUserDeviceCreateWithProperties` when the dext is not installed or approved
- **SystemExtensionManager** — GUI component for installing and approving the DriverKit extension
- **GIPAuthHandler** — CMD 0x06 authentication sub-protocol state machine for Xbox One / Series controllers, with dummy auth payloads (lenient enforcement)
- **GIPConstants** — protocol command bytes, option flags, device power states, and auth sub-protocol states extracted from Windows driver analysis
- **build-dext.sh** — script to build and embed the DriverKit extension into the GUI app bundle
- **build-release.sh** — universal binary build, codesign, and notarization pipeline
- Dext entitlements: `driverkit.transport.hid`, `driverkit.family.hid.eventservice`
- Stick-to-mouse and D-pad-to-arrow-keys mapping

### Changed

- **GIPParser** — integrated GIPAuthHandler, fixed extended-length packet encoding, replaced inline constants with GIPConstants enums
- **Output architecture** — replaced CGEvent-based output with virtual HID gamepad dispatchers (DriverKit primary, IOHIDUserDevice fallback)
- **Permissions** — removed Accessibility requirement; only Input Monitoring is needed now
- **Daemon entitlements** — clarified that `hid.virtual.device` was not granted; `driverkit.userclient-access` is the production path
- **build-dev.sh** — creates `.app` bundle structure for system extension support

### Fixed

- **build-release.sh** — added missing `--entitlements` flag to GUI codesign step
- Dext `allow-any-userclient-access` commented out with dev-only guidance (was active, should only be used for local development without provisioning profiles)
