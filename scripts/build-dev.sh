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

# ---------------------------------------------------------------------------
# Validate signing requirements
# ---------------------------------------------------------------------------
if [[ "$IDENTITY" == "-" ]]; then
    echo "ERROR: macOS 26+ requires Apple Development signing for restricted entitlements."
    echo "Set CODESIGN_IDENTITY in scripts/.env.dev"
    echo "Find your identity: security find-identity -v -p codesigning"
    exit 1
fi

for profile_var in DAEMON_PROFILE GUI_PROFILE; do
    profile_path="${!profile_var}"
    if [[ ! -f "$profile_path" ]]; then
        echo "ERROR: Provisioning profile not found: $profile_path"
        echo "Set ${profile_var/PROFILE/PROVISIONING_PROFILE} in scripts/.env.dev or install the profile."
        exit 1
    fi
done

echo "Building debug binaries..."
cd "$PROJECT_DIR"
swift build --product OpenJoystickDriverDaemon
swift build --product OpenJoystickDriver

# ---------------------------------------------------------------------------
# Resolve entitlements templates (replace ${DEVELOPMENT_TEAM} placeholder)
# ---------------------------------------------------------------------------
mkdir -p "$PROJECT_DIR/.build"
resolve_entitlements "$DAEMON_ENTITLEMENTS_TEMPLATE" "$DAEMON_ENTITLEMENTS"
resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"

# ---------------------------------------------------------------------------
# Create app bundle for GUI (required for system extension installation)
# ---------------------------------------------------------------------------
GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
GUI_CONTENTS="$GUI_APP/Contents"
GUI_MACOS="$GUI_CONTENTS/MacOS"

echo "Creating app bundle..."
rm -rf "$GUI_APP"
mkdir -p "$GUI_MACOS"
cp "$GUI_DEBUG" "$GUI_MACOS/OpenJoystickDriver"
cp "$DAEMON_DEBUG" "$GUI_MACOS/OpenJoystickDriverDaemon"

# Embed GUI provisioning profile in app bundle
cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"

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

# ---------------------------------------------------------------------------
# Create daemon mini-bundle (required for provisioning profile on macOS 26+)
# A standalone Mach-O cannot carry an embedded.provisionprofile — it must be
# inside a bundle structure for AMFI to find and validate the profile.
# ---------------------------------------------------------------------------
DAEMON_BUNDLE="$GUI_MACOS/OpenJoystickDriverDaemon.app"
DAEMON_BUNDLE_CONTENTS="$DAEMON_BUNDLE/Contents"
DAEMON_BUNDLE_MACOS="$DAEMON_BUNDLE_CONTENTS/MacOS"

echo "Creating daemon bundle..."
mkdir -p "$DAEMON_BUNDLE_MACOS"
cp "$DAEMON_DEBUG" "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
cp "$DAEMON_PROFILE" "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile"

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

# ---------------------------------------------------------------------------
# Sign everything (inside-out: binaries first, then bundles)
# ---------------------------------------------------------------------------
echo "Signing using: $IDENTITY"

# Sign daemon binary inside its bundle
ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
# Sign daemon bundle
codesign --sign "$IDENTITY" --force --generate-entitlement-der "$DAEMON_BUNDLE"

# Also keep a signed copy at the top level of MacOS/ for backward compat
# (LaunchAgent plist may still point here until re-installed)
ojd_sign "$GUI_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"

# Sign the outer app bundle (must be last, with GUI entitlements so the
# main executable retains system-extension.install)
codesign --sign "$IDENTITY" --force --generate-entitlement-der \
    --entitlements "$GUI_ENTITLEMENTS" "$GUI_APP"

echo ""
echo "Signed with: $IDENTITY"
echo "  GUI app:        $GUI_APP"
echo "  Daemon bundle:  $DAEMON_BUNDLE"
echo "  Daemon binary:  $DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
echo ""
echo "Run GUI:     open $GUI_APP"
echo ""
echo "To install DriverKit extension, run ./scripts/build-dext.sh after this."
