#!/usr/bin/env bash
# Full rebuild: app + dext, then verify bundle IDs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building app ==="
"$SCRIPT_DIR/build-dev.sh"

echo ""
echo "=== Building dext ==="
"$SCRIPT_DIR/build-dext.sh"

echo ""
echo "=== Verifying bundle IDs ==="
APP_ID=$(plutil -extract CFBundleIdentifier raw \
  .build/debug/OpenJoystickDriver.app/Contents/Info.plist 2>/dev/null || echo "MISSING")
# Dext is now named by bundle ID in Library/SystemExtensions/
DEXT_ID=$(plutil -extract CFBundleIdentifier raw \
  ".build/debug/OpenJoystickDriver.app/Contents/Library/SystemExtensions/${APP_ID}.VirtualHIDDevice.dext/Info.plist" 2>/dev/null || echo "MISSING")

echo "  App:  $APP_ID"
echo "  Dext: $DEXT_ID"

if [[ "$DEXT_ID" == "$APP_ID"* ]]; then
  echo "  ✓ Dext ID starts with app ID — prefix match OK"
else
  echo "  ✗ PREFIX MISMATCH — dext will not be found in app bundle"
  exit 1
fi

echo ""
echo "=== Launching from /Applications/ ==="
# Kill any running instance first — macOS Launch Services will reuse an
# already-running app with the same bundle ID instead of launching the new copy
killall OpenJoystickDriver 2>/dev/null || true
sleep 1
open /Applications/OpenJoystickDriver.app
echo "Done. Launched /Applications/OpenJoystickDriver.app"
