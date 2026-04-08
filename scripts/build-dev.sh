#!/usr/bin/env bash
# Build and sign both debug binaries (daemon + GUI).
#
# Requires CODESIGN_IDENTITY and provisioning profiles for macOS 26+.
# Restricted entitlements (system-extension.install, driverkit.userclient-access)
# require provisioning profiles to be honored by AMFI on Darwin 25+.
#
# USAGE:
#   ./scripts/build-dev.sh
#
# PREREQUISITES:
#   - scripts/.env.dev with CODESIGN_IDENTITY and DEVELOPMENT_TEAM
#   - Provisioning profiles installed in ~/Library/MobileDevice/Provisioning Profiles/
#     (or override DAEMON_PROVISIONING_PROFILE / GUI_PROVISIONING_PROFILE in .env.dev)
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ "$IDENTITY" == "-" ]]; then
    echo "ERROR: macOS 26+ requires Apple Development signing for restricted entitlements."
    echo "Set CODESIGN_IDENTITY in scripts/.env.dev"
    echo "Tip: run ./scripts/configure-signing.sh to auto-generate scripts/.env.dev"
    echo "Find your identity: security find-identity -v -p codesigning"
    exit 1
fi

for profile_var in DAEMON_PROFILE GUI_PROFILE; do
    profile_path="${!profile_var}"
    if [[ ! -f "$profile_path" ]]; then
        echo "ERROR: Provisioning profile not found: $profile_path"
        echo "Set ${profile_var/PROFILE/PROVISIONING_PROFILE} in scripts/.env.dev or install the profile."
        if [[ "$profile_path" == "$HOME/Library/MobileDevice/Provisioning Profiles/"* ]] && [[ ! -d "$HOME/Library/MobileDevice/Provisioning Profiles" ]]; then
            if [[ -d "$HOME/Documents/profiles" ]]; then
                echo ""
                echo "Note: $HOME/Library/MobileDevice/Provisioning Profiles/ does not exist yet."
                echo "      Profiles currently found in: $HOME/Documents/profiles"
                echo "      You can copy them into the expected directory or point the env var at the Documents path."
                echo "      Audit profiles (no sensitive output): ./scripts/profile-audit.sh"
            fi
        fi
        exit 1
    fi
done

# Fail fast if profiles cannot legally support the entitlements we are about to sign with.
#
# Without this, macOS may refuse to launch the app with:
#   RBSRequestErrorDomain Code=5 + NSPOSIXErrorDomain Code=163 (job spawn failed)
#
# IMPORTANT: This check does not print sensitive identifiers; it only names the missing entitlement key.
profile_has_entitlement() {
  local profile="$1" key="$2"
  python3 - "$profile" "$key" <<'PY'
import os, sys, plistlib, subprocess
profile, key = sys.argv[1], sys.argv[2]

def decode(path: str) -> bytes:
    # Prefer Apple tooling, but fall back to OpenSSL because `security cms -D` can fail on some machines.
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if p.returncode == 0 and p.stdout:
        return p.stdout
    return b""

try:
    raw = decode(profile)
    if not raw:
        print("decode_error")
        raise SystemExit(0)
    # OpenSSL output is usually a plist, but when it isn't, try to extract the XML payload.
    if b"<?xml" not in raw:
        print("decode_error")
        raise SystemExit(0)
    raw = raw[raw.index(b"<?xml") :]
    obj = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

ent = obj.get("Entitlements") or {}
print("true" if key in ent else "false")
PY
}

require_profile_entitlement() {
  local profile="$1" key="$2" what="$3" fix="$4"
  local ok
  ok="$(profile_has_entitlement "$profile" "$key" || echo "false")"
  if [[ "$ok" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not decode provisioning profile to check entitlements."
    echo "  profile: $profile"
    echo ""
    echo "Fix:"
    echo "  1) Reinstall profiles: ./scripts/install-profiles.sh"
    echo "  2) Audit profiles (safe output): ./scripts/profile-audit.sh \"$HOME/Library/MobileDevice/Provisioning Profiles\"/*.provisionprofile"
    exit 1
  fi
  if [[ "$ok" != "true" ]]; then
    echo ""
    echo "ERROR: Provisioning profile is missing entitlement: $key"
    echo "  profile: $profile"
    echo "  affects: $what"
    echo ""
    echo "$fix"
    exit 1
  fi
}

require_profile_entitlement \
  "$GUI_PROFILE" \
  "com.apple.developer.system-extension.install" \
  "GUI app (system extension install)" \
  "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with the System Extension install capability, then reinstall profiles (./scripts/install-profiles.sh)."

require_profile_entitlement \
  "$GUI_PROFILE" \
  "com.apple.developer.hid.virtual.device" \
  "GUI app (Compatibility / embedded backend IOHIDUserDevice)" \
  "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with entitlement com.apple.developer.hid.virtual.device, then reinstall profiles (./scripts/install-profiles.sh)."

require_profile_entitlement \
  "$DAEMON_PROFILE" \
  "com.apple.developer.hid.virtual.device" \
  "Daemon (Compatibility IOHIDUserDevice)" \
  "Fix: enable entitlement com.apple.developer.hid.virtual.device on Identifier com.openjoystickdriver.daemon, regenerate the daemon provisioning profile, then reinstall profiles (./scripts/install-profiles.sh)."

# For release builds routed through rebuild.sh, link against our static
# universal libusb instead of Homebrew's dynamic dylib. This avoids a
# Team ID mismatch SIGKILL under hardened runtime + library validation.
if [[ "$OJD_ENV" == "release" ]]; then
  setup_libusb_pkgconfig
fi

if [[ "$OJD_ENV" == "release" ]]; then
  echo "Building release binaries (universal)..."
  cd "$PROJECT_DIR"
  swift build -c release --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 \
    -Xswiftc -warnings-as-errors
  swift build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64 \
    -Xswiftc -warnings-as-errors
else
  echo "Building debug binaries..."
  cd "$PROJECT_DIR"
  swift build --product OpenJoystickDriverDaemon -Xswiftc -warnings-as-errors
  swift build --product OpenJoystickDriver -Xswiftc -warnings-as-errors
fi

mkdir -p "$PROJECT_DIR/.build"
resolve_entitlements "$DAEMON_ENTITLEMENTS_TEMPLATE" "$DAEMON_ENTITLEMENTS"
resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"

GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
GUI_CONTENTS="$GUI_APP/Contents"
GUI_MACOS="$GUI_CONTENTS/MacOS"

echo "Creating app bundle..."
rm -rf "$GUI_APP"
mkdir -p "$GUI_MACOS"
cp "$GUI_BIN" "$GUI_MACOS/OpenJoystickDriver"
cp "$DAEMON_BIN" "$GUI_MACOS/OpenJoystickDriverDaemon"

# Copy SPM resource bundles so Bundle.module resolves at runtime
BUILD_DIR="$(dirname "$DAEMON_BIN")"
GUI_RESOURCES="$GUI_CONTENTS/Resources"
mkdir -p "$GUI_RESOURCES"
for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$GUI_RESOURCES/"
done

# Embed LaunchAgent plist for SMAppService-based daemon management.
#
# This must exist at:
#   OpenJoystickDriver.app/Contents/Library/LaunchAgents/com.openjoystickdriver.daemon.plist
LAUNCHAGENTS_SRC="$PROJECT_DIR/Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
LAUNCHAGENTS_DST="$GUI_CONTENTS/Library/LaunchAgents"
mkdir -p "$LAUNCHAGENTS_DST"
cp "$LAUNCHAGENTS_SRC" "$LAUNCHAGENTS_DST/com.openjoystickdriver.daemon.plist"

# Embed GUI provisioning profile in app bundle
cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"
xattr -d com.apple.quarantine "$GUI_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

# Write Info.plist
cat > "$GUI_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleDisplayName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSystemExtensionUsageDescription</key>
    <string>OpenJoystickDriver uses this extension to present physical controllers as a standard virtual HID gamepad to games and applications, without requiring Accessibility permission.</string>
</dict>
</plist>
PLIST

DAEMON_BUNDLE="$GUI_MACOS/OpenJoystickDriverDaemon.app"
DAEMON_BUNDLE_CONTENTS="$DAEMON_BUNDLE/Contents"
DAEMON_BUNDLE_MACOS="$DAEMON_BUNDLE_CONTENTS/MacOS"

echo "Creating daemon bundle..."
mkdir -p "$DAEMON_BUNDLE_MACOS"
cp "$DAEMON_BIN" "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
cp "$DAEMON_PROFILE" "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile"
xattr -d com.apple.quarantine "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

# Copy SPM resource bundles into daemon mini-bundle
DAEMON_RESOURCES="$DAEMON_BUNDLE_CONTENTS/Resources"
mkdir -p "$DAEMON_RESOURCES"
for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$DAEMON_RESOURCES/"
done

cat > "$DAEMON_BUNDLE_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver.daemon</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing using: $IDENTITY"

# Sign daemon binary inside its bundle
ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
# Sign daemon bundle (must also pass entitlements — bundle signing re-signs the binary)
ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"

# Also keep a signed copy at the top level of MacOS/ for backward compat
# (LaunchAgent plist may still point here until re-installed)
ojd_sign "$GUI_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"

# Sign the outer app bundle (must be last, with GUI entitlements so the
# main executable retains system-extension.install)
ojd_sign "$GUI_APP" --entitlements "$GUI_ENTITLEMENTS"

# Re-apply daemon entitlements — outer app signing overwrites nested code signatures,
# stripping the daemon's entitlements (e.g. driverkit.userclient-access).
ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"

# Verify provisioning profile certs match signing identity (release only).
# Catches cert mismatch early instead of AMFI rejecting at launch (error 163).
if [[ "$OJD_ENV" == "release" ]]; then
  verify_profile_cert "$GUI_PROFILE" "$IDENTITY"
  verify_profile_cert "$DAEMON_PROFILE" "$IDENTITY"
fi

echo ""
echo "Signed with: $IDENTITY"
echo "  GUI app:        $GUI_APP"
echo "  Daemon bundle:  $DAEMON_BUNDLE"
echo "  Daemon binary:  $DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
echo ""
echo "Run GUI:     open $GUI_APP"
echo ""
echo "To install DriverKit extension, run ./scripts/build-dext.sh after this."
