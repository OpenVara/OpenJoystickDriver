#!/usr/bin/env bash
# Full rebuild: nuke, build, deploy, activate, verify.
# The only script a developer runs during iteration.
#
# Use OJD_ENV=release for Developer ID signing + notarization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# zsh has a 'log' builtin that shadows /usr/bin/log — always use full path
LOG=/usr/bin/log
DEXT_PLIST="$SCRIPT_DIR/../DriverKitExtension/Info.plist"

echo "=== Step 1: Nuke all stale state ==="
"$SCRIPT_DIR/nuke.sh"

echo ""
echo "=== Step 2: Bump CFBundleVersion ==="
OLD_VERSION=$(plutil -extract CFBundleVersion raw "$DEXT_PLIST" 2>/dev/null || echo "0")
NEW_BUILD_VERSION=$(( OLD_VERSION + 1 ))
plutil -replace CFBundleVersion -string "$NEW_BUILD_VERSION" "$DEXT_PLIST"
echo "  Bumped CFBundleVersion: $OLD_VERSION → $NEW_BUILD_VERSION"

echo ""
echo "=== Step 3: Build app ==="
"$SCRIPT_DIR/build-dev.sh"

echo ""
echo "=== Step 4: Build dext ==="
"$SCRIPT_DIR/build-dext.sh"

echo ""
echo "=== Step 5: Verify bundle IDs ==="
APP_ID=$(plutil -extract CFBundleIdentifier raw \
  .build/debug/OpenJoystickDriver.app/Contents/Info.plist 2>/dev/null || echo "MISSING")
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

if [[ "$OJD_ENV" == "release" ]]; then
  echo ""
  echo "=== Notarizing ==="
  "$SCRIPT_DIR/notarize.sh"
fi

echo ""
echo "=== Step 6: Launch app ==="
: > /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || true
: > /tmp/com.openjoystickdriver.daemon.err 2>/dev/null || true

open /Applications/OpenJoystickDriver.app
echo "  Launched /Applications/OpenJoystickDriver.app"

echo ""
echo "=== Step 7: Wait for sysext activation ==="
echo "  Click 'Install Extension' in the app if prompted…"
echo ""

NEW_VERSION=$(plutil -extract CFBundleVersion raw \
  /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext/Info.plist 2>/dev/null || echo "")
SYSEXT_TIMEOUT=30
SYSEXT_ELAPSED=0
while (( SYSEXT_ELAPSED < SYSEXT_TIMEOUT )); do
  sleep 2
  SYSEXT_ELAPSED=$(( SYSEXT_ELAPSED + 2 ))
  if systemextensionsctl list 2>&1 | grep -q "1.0/${NEW_VERSION}.*activated enabled"; then
    echo "  ✓ Sysext v${NEW_VERSION} activated after ${SYSEXT_ELAPSED}s"
    break
  fi
  printf "  …waiting for sysext v%s (%ds)\n" "$NEW_VERSION" "$SYSEXT_ELAPSED"
done

if (( SYSEXT_ELAPSED >= SYSEXT_TIMEOUT )); then
  echo "  ⚠ Sysext v${NEW_VERSION} not activated after ${SYSEXT_TIMEOUT}s — continuing anyway"
fi

# Do NOT kill the dext here — sysext activation already replaced it.
# Killing it would destroy the IOUserService (Manager) personality, which
# the kernel does not auto-restart (only AppleUserHIDDevice auto-restarts).

echo ""
echo "=== Step 8: Wait for dext start ==="

TIMEOUT=60
ELAPSED=0
while (( ELAPSED < TIMEOUT )); do
  sleep 3
  ELAPSED=$(( ELAPSED + 3 ))

  # Check for start failure
  if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' \
       --info --debug --style compact 2>/dev/null | grep -q "start fail"; then
    echo "  ✗ Kernel DK log shows 'start fail' after ${ELAPSED}s"
    break
  fi

  # Check for user server timeout
  if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' \
       --info --debug --style compact 2>/dev/null | grep -q "user server timeout"; then
    echo "  ✗ Kernel DK log shows 'user server timeout' after ${ELAPSED}s"
    break
  fi

  # Check for successful dext os_log output
  if $LOG show --last 10s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID:"' \
       --info --debug --style compact 2>/dev/null | grep -q "OpenJoystickVirtualHID:"; then
    echo "  ✓ Dext logs detected after ${ELAPSED}s"
    break
  fi

  printf "  …%ds\n" "$ELAPSED"
done

if (( ELAPSED >= TIMEOUT )); then
  echo "  ⚠ Timed out after ${TIMEOUT}s — no dext logs or start fail detected"
fi

echo ""
echo "=== Step 9: Restart daemon ==="

DAEMON_PLIST=~/Library/LaunchAgents/com.openjoystickdriver.daemon.plist
DAEMON_BIN_PATH="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
DAEMON_LABEL="com.openjoystickdriver.daemon"

mkdir -p ~/Library/LaunchAgents
cat > "$DAEMON_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${DAEMON_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${DAEMON_BIN_PATH}</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>com.openjoystickdriver.xpc</key>
    <true/>
  </dict>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/tmp/${DAEMON_LABEL}.err</string>
  <key>StandardOutPath</key>
  <string>/tmp/${DAEMON_LABEL}.out</string>
</dict>
</plist>
EOF
echo "  Wrote $DAEMON_PLIST"

launchctl bootstrap "gui/$(id -u)" "$DAEMON_PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$DAEMON_LABEL" 2>/dev/null \
  && echo "  ✓ Daemon restarted" \
  || echo "  ⚠ Daemon kickstart failed"
sleep 3

echo ""
echo "=== Step 10: Diagnostics ==="

echo "--- Dext os_log (last 60s) ---"
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
echo "--- Processes ---"
ps -eo pid,comm 2>/dev/null | grep -i "openjoystick\|VirtualHID" | grep -v grep || echo "(none running)"

echo ""
echo "--- HID Device in ioreg ---"
ioreg -r -c IOUserHIDDevice 2>/dev/null | head -5 || echo "(not found)"

echo ""
echo "--- hidutil ---"
hidutil list 2>/dev/null | grep -i "openjoystick\|045E.*02EA\|Xbox" || echo "(not found)"

echo ""
echo "--- Daemon log (fresh) ---"
tail -10 /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || echo "(no daemon log)"
