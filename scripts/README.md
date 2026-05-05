# Signing, Profiles, Notarization

This folder contains the build/signing scripts for OpenJoystickDriver.

## One-time setup

### 1) Install provisioning profiles

The scripts look for provisioning profiles at:

- `~/Library/MobileDevice/Provisioning Profiles/`

Install (copies from `~/Documents/Profiles/` or `~/Documents/profiles/`):

```bash
./scripts/ojd signing install-profiles
```

Expected filenames:

- `OpenJoystickDriver.provisionprofile` (GUI, Apple Development)
- `OpenJoystickDriver_DevID.provisionprofile` (GUI, Developer ID)
- `OpenJoystickDriverDaemon.provisionprofile` (daemon, Apple Development)
- `OpenJoystickDriverDaemon_DevID.provisionprofile` (daemon, Developer ID)
- `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` (DriverKit dext, Apple Development)

Sanity-check what you installed (safe output; no identifiers printed):

```bash
./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
```

If something fails, run the signing doctor (safe output; no Apple ID / no full subjects):

```bash
./scripts/ojd signing doctor
```

### 2) Ensure Keychain identities exist

You should see at least:

- `Apple Development: …`
- `Developer ID Application: …`

```bash
security find-identity -v -p codesigning
```

The Team ID in your provisioning profiles must match the Team ID encoded in your certificate **Subject OU**.
Do not trust the `(...)` suffix in the Keychain display name as the Team ID.

If Keychain Access shows “not trusted” but `security find-identity` says the identity is valid, you can usually ignore the UI.

If `security find-identity` shows **0 valid identities**, you’re missing Apple’s intermediate CA certificates (WWDR / Developer ID).
Get them from Apple’s Certificate Authority page and import them in Keychain Access (System keychain is fine), then re-check `find-identity`:

```text
https://www.apple.com/certificateauthority/
```

### “Keychain Access shows certs, but security says 0 identities”

If the Keychain UI shows certs + private keys but `security find-identity` prints `0 valid identities found`, your keychain file permissions are wrong.

Fix:

```bash
chmod 700 "$HOME/Library/Keychains"
chmod 600 "$HOME/Library/Keychains/login.keychain-db"
```

Then log out/in (or reboot) and try again.

### Team/certificate mismatch (most common)

If you have a `Developer ID Application` cert for one team, but your `Apple Development` cert is for a different team, xcodebuild will fail with:

- “Provisioning profile … doesn’t include signing certificate …”
- or “No certificate for team … matching …”

Commands to see what you have (prints only Team IDs):

```bash
# Team ID in your Apple Development .cer (from ~/Documents/Certificates)
# NOTE: the Team ID is the certificate Subject OU (not the display-name (...) suffix).
openssl x509 -inform DER -in "$HOME/Documents/Certificates/development.cer" -noout -subject -nameopt RFC2253 \
  | sed -nE 's/.*OU=([^,]+).*/\\1/p'

# Team ID inside the DriverKit provisioning profile
openssl smime -inform der -verify -noverify \
  -in "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile" 2>/dev/null \
  | plutil -extract TeamIdentifier.0 raw -o - -
```

If those Team IDs differ:

1. Create an **Apple Development** certificate for the **same team** as the provisioning profiles (Developer portal → Certificates → `+` → Apple Development).
2. Import the downloaded `.cer` into Keychain Access (it must include a private key).
3. Regenerate the **Apple Development** provisioning profiles (GUI, daemon, dext) selecting that new Apple Development certificate.
4. Reinstall profiles: `./scripts/ojd signing install-profiles`
5. Re-generate env files: `./scripts/ojd signing configure`

For the entitlement `com.apple.developer.hid.virtual.device`:

- It must be present on the **Identifier that creates the user-space virtual device (IOHIDUserDevice)**.
  In this repo that can be:
  - **Daemon** (normal path): `OpenJoystickDriverDaemon.provisionprofile` (dev) and `OpenJoystickDriverDaemon_DevID.provisionprofile` (release)
  - **GUI app** (embedded fallback path): `OpenJoystickDriver.provisionprofile` (dev) and `OpenJoystickDriver_DevID.provisionprofile` (release)

The DriverKit `.dext` does **not** use IOHIDUserDevice and does not need `com.apple.developer.hid.virtual.device`.

### If Keychain shows the “wrong” Team ID in the certificate name

Apple certificates encode the team ID in the **Subject OU**. Some tooling/UI also shows an identifier in the
certificate’s **CN** (the `(...)` part of the display name). If those disagree, use the provisioning profile’s
`TeamIdentifier` (and the certificate Subject OU) as the source of truth and sign by **SHA1 identity** instead of the display name.

This repo’s `./scripts/ojd signing configure` writes `CODESIGN_IDENTITY` as a 40‑hex SHA1 for that reason.

### 3) Generate `scripts/.env.dev` and `scripts/.env.release`

This repo has a helper that reads your Keychain + installed profiles and writes both env files:

```bash
./scripts/ojd signing configure
```

## Common tasks

### Daemon install / restart (no launchctl)

Daemon lifecycle is managed via macOS ServiceManagement (`SMAppService`) from inside the app bundle.
Do not use `launchctl bootstrap` manually.

Commands (run the app-bundled binary):

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless install
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless uninstall
```

### Dev build (signed) + app bundle

```bash
./scripts/ojd build dev
```

### Build the DriverKit system extension (.dext)

```bash
./scripts/ojd build dext
```

### If DriverKit build fails with “No certificate for team … matching …”

If you see an error like:

```text
No certificate for team '9PQP6CDMQT' matching 'Apple Development: … (XXXXXXXXXX)' found
```

Do **not** assume your Team ID is wrong. This is often caused by Xcode matching based on the
certificate display name suffix `(...)`.

Fix:

1) Re-run `./scripts/ojd signing configure` so `CODESIGN_IDENTITY` is a SHA1 fingerprint.
2) Re-run `./scripts/ojd build dext` (this prefers SHA1 for xcodebuild).

## Notarization

Create an app-specific password:

```text
https://account.apple.com/  → Sign-In and Security → App-Specific Passwords
```

Put these into `scripts/.env.release`:

- `NOTARIZE_APPLE_ID` (your Apple ID email)
- `NOTARIZE_PASSWORD` (the app-specific password)

Then:

```bash
OJD_ENV=release ./scripts/ojd rebuild release
OJD_ENV=release ./scripts/ojd notarize submit
OJD_ENV=release ./scripts/ojd notarize status
```

### Tester package

For a tester build that does not install anything on the build machine:

```bash
./scripts/ojd package tester 0.1.0-test.1
```

This command uses release signing, embeds the DriverKit extension into the app
bundle, submits the app for notarization, staples the accepted ticket, verifies
the result, and writes:

```text
.build/release-artifacts/OpenJoystickDriver-<version>-macOS.zip
```

The package command does not register the LaunchAgent and does not submit a
system-extension activation request on the build machine. Testers still need to
install and approve the app/system extension locally.

## GitHub Actions tester release

`.github/workflows/release-tester.yml` runs on `v*` tags and by manual dispatch.
It installs `libusb`, validates profiles, imports signing material, builds a
release app, notarizes it, and uploads the tester zip as a workflow artifact.

Required repository secrets:

- `APPLE_DEVELOPMENT_CERT_BASE64`
- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `CERTIFICATE_SECRET`
- `KEYCHAIN_SECRET`
- `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_PASSWORD`

The certificate payload secrets are base64-encoded certificate export files.
The profile secrets are base64-encoded `.provisionprofile` files.
