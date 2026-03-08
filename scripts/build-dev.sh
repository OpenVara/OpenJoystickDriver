#!/usr/bin/env bash
# Build and sign both debug binaries (daemon + GUI).
#
# Signs with CODESIGN_IDENTITY if set, otherwise ad-hoc (-).
# Ad-hoc signing embeds entitlements but macOS does NOT enforce them on Darwin 25+.
# Set CODESIGN_IDENTITY to Apple Development cert for USB entitlement enforcement.
#
# USAGE:
#   ./scripts/build-dev.sh
#   CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-dev.sh
#
# Find your signing identity:
#   security find-identity -v -p codesigning
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "Building debug binaries..."
cd "$PROJECT_DIR"
swift build --product OpenJoystickDriverDaemon
swift build --product OpenJoystickDriver

echo "Signing daemon (with entitlements) using: $IDENTITY"
ojd_sign "$DAEMON_DEBUG" --entitlements "$ENTITLEMENTS"

# ---------------------------------------------------------------------------
# Create app bundle for GUI (required for system extension installation)
# ---------------------------------------------------------------------------
GUI_ENTITLEMENTS="$PROJECT_DIR/Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements"
GUI_INFO_PLIST="$PROJECT_DIR/Sources/OpenJoystickDriver/App/Info.plist"
GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
GUI_CONTENTS="$GUI_APP/Contents"
GUI_MACOS="$GUI_CONTENTS/MacOS"

echo "Creating app bundle..."
mkdir -p "$GUI_MACOS"
cp "$GUI_DEBUG" "$GUI_MACOS/OpenJoystickDriver"
cp "$DAEMON_DEBUG" "$GUI_MACOS/OpenJoystickDriverDaemon"

# Merge Info.plist with required bundle keys
cat > "$GUI_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver.app</string>
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

echo "Signing GUI app bundle using: $IDENTITY"
ojd_sign "$GUI_MACOS/OpenJoystickDriver" --entitlements "$GUI_ENTITLEMENTS"
ojd_sign "$GUI_MACOS/OpenJoystickDriverDaemon" --entitlements "$ENTITLEMENTS"
codesign --sign "$IDENTITY" --force "$GUI_APP"

echo ""
echo "Signed with: $IDENTITY"
echo "  Daemon: $GUI_MACOS/OpenJoystickDriverDaemon"
echo "  GUI:    $GUI_APP"
echo ""
if [[ "$IDENTITY" == "-" ]]; then
  echo "Note: ad-hoc signed. On Darwin 25+ (macOS 26), sudo may not be enough"
  echo "  for USB class 0xFF access. Set CODESIGN_IDENTITY to your Apple"
  echo "  Development cert to have USB entitlement enforced properly."
  echo "  Find it: security find-identity -v -p codesigning"
  echo ""
fi
echo "Run daemon:  sudo $GUI_MACOS/OpenJoystickDriverDaemon"
echo "Run GUI:     open $GUI_APP"
echo ""
echo "To install DriverKit extension, run ./scripts/build-dext.sh after this."
