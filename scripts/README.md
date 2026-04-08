# Signing, Profiles, Notarization

This folder contains the build/signing scripts for OpenJoystickDriver.

## One-time setup

### 1) Install provisioning profiles

The scripts look for provisioning profiles at:

- `~/Library/MobileDevice/Provisioning Profiles/`

Install (copies from `~/Documents/Profiles/` or `~/Documents/profiles/`):

```bash
./scripts/install-profiles.sh
```

Expected filenames:

- `OpenJoystickDriver.provisionprofile` (GUI, Apple Development)
- `OpenJoystickDriver_DevID.provisionprofile` (GUI, Developer ID)
- `OpenJoystickDriverDaemon.provisionprofile` (daemon, Apple Development)
- `OpenJoystickDriverDaemon_DevID.provisionprofile` (daemon, Developer ID)
- `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` (DriverKit dext, Apple Development)

Sanity-check what you installed (safe output; no identifiers printed):

```bash
./scripts/profile-audit.sh "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile
```

If something fails, run the signing doctor (safe output; no Apple ID / no full subjects):

```bash
./scripts/doctor-signing.sh
```

### 2) Ensure Keychain identities exist

You should see at least:

- `Apple Development: …`
- `Developer ID Application: …`

```bash
security find-identity -v -p codesigning
```

The Team ID in the identity name (the `(...)` suffix) must match the Team ID in the provisioning profiles you installed.

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
openssl x509 -inform DER -in "$HOME/Documents/Certificates/development.cer" -noout -subject \
  | sed -nE 's/.*\\(([A-Z0-9]{10})\\).*/\\1/p'

# Team ID inside the DriverKit provisioning profile
openssl smime -inform der -verify -noverify \
  -in "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile" 2>/dev/null \
  | plutil -extract TeamIdentifier.0 raw -o - -
```

If those Team IDs differ:

1. Create an **Apple Development** certificate for the **same team** as the provisioning profiles (Developer portal → Certificates → `+` → Apple Development).
2. Import the downloaded `.cer` into Keychain Access (it must include a private key).
3. Regenerate the **Apple Development** provisioning profiles (GUI, daemon, dext) selecting that new Apple Development certificate.
4. Reinstall profiles: `./scripts/install-profiles.sh`
5. Re-generate env files: `./scripts/configure-signing.sh`

For the entitlement `com.apple.developer.hid.virtual.device`:

- **DriverKit dext profile** must have it:
  `OpenJoystickDriver_VirtualHIDDevice.provisionprofile` (bundle id suffix `com.openjoystickdriver.VirtualHIDDevice`)
- If you enable the app’s **SDL Compatibility (User-Space Virtual Device)** mode, the **daemon profile** must also have it:
  `OpenJoystickDriverDaemon.provisionprofile` (dev) and `OpenJoystickDriverDaemon_DevID.provisionprofile` (release)

### If Keychain shows the “wrong” Team ID in the certificate name

Apple certificates encode the team ID in the **Subject OU**. Some tooling/UI also shows an identifier in the
certificate’s **CN** (the `(...)` part of the display name). If those disagree, use the provisioning profile’s
`TeamIdentifier` as the source of truth and sign by **SHA1 identity** instead of the display name.

This repo’s `./scripts/configure-signing.sh` writes `CODESIGN_IDENTITY` as a 40‑hex SHA1 for that reason.

### 3) Generate `scripts/.env.dev` and `scripts/.env.release`

This repo has a helper that reads your Keychain + installed profiles and writes both env files:

```bash
./scripts/configure-signing.sh
```

## Common tasks

### Dev build (signed) + app bundle

```bash
./scripts/build-dev.sh
```

### Build the DriverKit system extension (.dext)

```bash
./scripts/build-dext.sh
```

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
OJD_ENV=release ./scripts/rebuild.sh
OJD_ENV=release ./scripts/notarize.sh
OJD_ENV=release ./scripts/notarize-status.sh
```
