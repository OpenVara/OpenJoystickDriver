#!/usr/bin/env bash
# Full rebuild: app + dext, then verify bundle IDs.
# Use OJD_ENV=release for Developer ID signing + notarization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OJD_ENV="${OJD_ENV:-dev}"

# zsh has a 'log' builtin that shadows /usr/bin/log — always use full path
LOG=/usr/bin/log

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

# ---------------------------------------------------------------------------
# Notarize for release builds (must happen after install to /Applications)
# ---------------------------------------------------------------------------
if [[ "$OJD_ENV" == "release" ]]; then
  echo ""
  echo "=== Notarizing ==="
  "$SCRIPT_DIR/notarize.sh"
fi

echo ""
echo "=== Pre-launch cleanup ==="
killall OpenJoystickDriver 2>/dev/null || true
killall OpenJoystickVirtualHID 2>/dev/null || true

# Warn if installed sysext binary is not executable (sysextd crash can corrupt permissions)
for sysext_dir in /Library/SystemExtensions/*/com.openjoystickdriver.VirtualHIDDevice.dext; do
  binary="$sysext_dir/OpenJoystickVirtualHID"
  if [[ -f "$binary" && ! -x "$binary" ]]; then
    echo "  ⚠ Installed sysext binary is not executable: $binary"
    echo "    Stale sysext state detected — a reboot may be required."
  fi
done

sleep 1

echo ""
echo "=== Launching from /Applications/ ==="
open /Applications/OpenJoystickDriver.app
echo "Done. Launched /Applications/OpenJoystickDriver.app"

echo ""
echo "=== Waiting for sysext activation + dext start ==="
echo "Click 'Install Extension' in the app, then wait…"
echo ""

# Poll for up to 60s until the dext logs appear or start fail is detected
TIMEOUT=60
ELAPSED=0
while (( ELAPSED < TIMEOUT )); do
  sleep 3
  ELAPSED=$(( ELAPSED + 3 ))

  # Check for start failure
  if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' \
       --info --debug --style compact 2>/dev/null | grep -q "start fail"; then
    echo "✗ Kernel DK log shows 'start fail' after ${ELAPSED}s"
    break
  fi

  # Check for user server timeout
  if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' \
       --info --debug --style compact 2>/dev/null | grep -q "user server timeout"; then
    echo "✗ Kernel DK log shows 'user server timeout' after ${ELAPSED}s"
    break
  fi

  # Check for successful dext os_log output
  if $LOG show --last 10s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID:"' \
       --info --debug --style compact 2>/dev/null | grep -q "OpenJoystickVirtualHID:"; then
    echo "✓ Dext logs detected after ${ELAPSED}s"
    break
  fi

  printf "  …%ds\n" "$ELAPSED"
done

if (( ELAPSED >= TIMEOUT )); then
  echo "⚠ Timed out after ${TIMEOUT}s — no dext logs or start fail detected"
fi

echo ""
echo "--- Dext os_log output (last 60s) ---"
$LOG show --last 60s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID"' \
  --info --debug --style compact 2>/dev/null || echo "(none)"

echo ""
echo "--- Kernel DK logs (last 60s) ---"
$LOG show --last 60s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' \
  --info --debug --style compact 2>/dev/null || echo "(none)"

echo ""
echo "--- Sysext status ---"
systemextensionsctl list 2>&1 || true

echo ""
echo "--- IOUserHIDDevice in ioreg ---"
ioreg -r -c IOUserHIDDevice 2>/dev/null | head -20 || echo "(not found)"
