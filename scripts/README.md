# Signing, Profiles, Notarization

This folder contains the build/signing tooling for OpenJoystickDriver.

## Task Map

| Goal | Command | Notes |
| --- | --- | --- |
| Install profiles into `~/Library/MobileDevice/Provisioning Profiles/` | `./scripts/ojd signing install-profiles` | Copies from `~/Documents/Profiles/` (or `profiles/`). |
| Check installed profiles (safe output) | `./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile` | No identifiers printed. |
| Generate `.env.dev` + `.env.release` | `./scripts/ojd signing configure` | Re-run after changing certs/profiles. |
| Diagnose common signing mismatches (safe output) | `./scripts/ojd signing doctor` | Use this before tweaking Xcode settings. |
| Build a signed dev app into `.build/` | `./scripts/ojd build dev` | Does not install. |
| Install a signed dev build into `/Applications` | `./scripts/ojd rebuild dev` | App, daemon, and (optionally) dext. |
| Fast rebuild app only (no dext upgrade) | `./scripts/ojd rebuild-fast dev` | Best when you are iterating while streaming. |
| Package a release DMG | `./scripts/ojd package release <version>` | Builds, notarizes, staples, and writes a DMG. |

## Initial Setup (Per Machine / Team)

### 1. Provisioning profiles

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

### 2. Keychain identities

You should see at least:

- `Apple Development: …`
- `Developer ID Application: …`

```bash
security find-identity -v -p codesigning
```

The Team ID in your provisioning profiles must match the Team ID encoded in your certificate **Subject OU**.
You must not trust the `(...)` suffix in the Keychain display name as the Team ID.

If `security find-identity` shows **0 valid identities**, you are usually missing Apple intermediate CA
certificates (WWDR / Developer ID). Apple publishes them here:

- https://www.apple.com/certificateauthority/

### 3. Generate `.env.dev` and `.env.release`

This repo reads your Keychain + installed profiles and writes both env files:

```bash
./scripts/ojd signing configure
```

Re-run this after rotating certificates, regenerating profiles, or switching teams.

## Common Tasks

### Daemon install / restart

On macOS 13 and newer, daemon lifecycle is managed through `SMAppService` from
inside the app bundle. On macOS 10.15 through 12, OJD installs the bundled
LaunchAgent plist through `launchctl`.

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

If DriverKit build fails due to certificate matching, see the Troubleshooting section below.

## Notarization

Store notarization credentials in the macOS Keychain:

```bash
OJD_ENV=release ./scripts/ojd notarize store-credentials OJDNotary
```

Put these into `.env.release`:

- `NOTARIZE_KEYCHAIN_PROFILE` (the notarytool Keychain profile name)

Then:

```bash
OJD_ENV=release ./scripts/ojd rebuild release
OJD_ENV=release ./scripts/ojd notarize submit
OJD_ENV=release ./scripts/ojd notarize status
```

### Release package

For a release build that does not install anything on the build machine:

```bash
./scripts/ojd package release 0.4.1
```

This command uses release signing, embeds the DriverKit extension into the app
bundle, submits the app for notarization, staples the accepted ticket, verifies
the result, and writes a drag-and-drop DMG containing `OpenJoystickDriver.app`
and an `Applications` symlink:

```text
.build/release-artifacts/OpenJoystickDriver-<version>-macOS.dmg
```

The package command does not register the LaunchAgent and does not submit a
system-extension activation request on the build machine. Testers still need to
install and approve the app/system extension locally.

## GitHub Actions release

`.github/workflows/release.yml` runs on SemVer tags such as `0.1.0` or
`0.4.1` and by manual dispatch.
It installs `libusb`, validates profiles, imports signing material, builds a
release app, notarizes it, uploads the release DMG as a workflow artifact, and
publishes the GitHub Release.

### Required repository secrets

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

### Generate GitHub secrets locally

To collect all release secrets in one local step:

```bash
./scripts/ojd signing export-github-secrets --repo xsyetopz/OpenJoystickDriver
```

If identity export paths are not supplied, the script exports signing identities
from your login keychain into the private output directory. Keychain may prompt
for permission. The script reads the three installed release provisioning
profiles, prompts for the identity export password and notarization credentials,
generates a temporary CI keychain password, then writes:

```text
.build/github-actions-secrets/
  values/*.txt
  apply-github-secrets.sh
```

To import them into GitHub with `gh`:

```bash
.build/github-actions-secrets/apply-github-secrets.sh --repo xsyetopz/OpenJoystickDriver
```

Or do both steps in one command:

```bash
./scripts/ojd signing export-github-secrets --repo xsyetopz/OpenJoystickDriver --apply
```

Keep `.build/github-actions-secrets/` private. It contains raw secret values.

If you already exported separate signing identity files from Keychain Access,
pass them explicitly with `--apple-development-identity` and
`--developer-id-identity`.

## Troubleshooting

<details>
<summary>Keychain Access shows certs, but <code>security find-identity</code> prints 0 identities</summary>

If the Keychain UI shows certs + private keys but `security find-identity` prints
`0 valid identities found`, your keychain file permissions are wrong.

Fix:

```bash
chmod 700 "$HOME/Library/Keychains"
chmod 600 "$HOME/Library/Keychains/login.keychain-db"
```

Then log out/in (or reboot) and try again.

</details>

<details>
<summary>Team/certificate mismatch (most common)</summary>

If you have a `Developer ID Application` cert for one team but your `Apple Development`
cert is for a different team, `xcodebuild` will fail with:

- “Provisioning profile … doesn’t include signing certificate …”
- “No certificate for team … matching …”

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

1. Create an **Apple Development** certificate for the **same team** as the provisioning profiles.
2. Import the downloaded `.cer` into Keychain Access (it must include a private key).
3. Regenerate the Apple Development provisioning profiles (GUI, daemon, dext) selecting that certificate.
4. Reinstall profiles: `./scripts/ojd signing install-profiles`
5. Re-generate env files: `./scripts/ojd signing configure`

Entitlement note for `com.apple.developer.hid.virtual.device`:

- It must be present on the identifier that creates the user-space virtual device (IOHIDUserDevice).
- In this repo that can be the daemon or the GUI app.
- The DriverKit `.dext` does not use IOHIDUserDevice and does not need this entitlement.

</details>

<details>
<summary>DriverKit build fails with “No certificate for team … matching …”</summary>

If you see an error like:

```text
No certificate for team '9PQP6CDMQT' matching 'Apple Development: … (XXXXXXXXXX)' found
```

This is often caused by Xcode matching based on the certificate display name suffix `(...)`.

Fix:

1. Re-run `./scripts/ojd signing configure` so `CODESIGN_IDENTITY` is a SHA1 fingerprint.
2. Re-run `./scripts/ojd build dext` (this prefers SHA1 for `xcodebuild`).

</details>
