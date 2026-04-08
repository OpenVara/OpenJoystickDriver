#!/usr/bin/env bash
# Obliterate every trace of OpenJoystickDriver from the running system.
# Single source of truth for cleanup — rebuild.sh delegates here.
# Safe to run multiple times. Requires sudo for dext/sysext cleanup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PID=$$

BUNDLE_ID="com.openjoystickdriver"
DEXT_BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
DAEMON_LABEL="com.openjoystickdriver.daemon"
APP_PATH="/Applications/OpenJoystickDriver.app"

echo "=== NUKE: killing every OJD process ==="

# App and daemon (by name)
killall -9 OpenJoystickDriver 2>/dev/null && echo "  killed OpenJoystickDriver" || true
killall -9 OpenJoystickDriverDaemon 2>/dev/null && echo "  killed OpenJoystickDriverDaemon" || true
killall -9 OpenJoystickVirtualHID 2>/dev/null && echo "  killed OpenJoystickVirtualHID" || true

# Dext process (runs as _driverkit, needs sudo, match by bundle ID)
for pid in $(pgrep -f "$DEXT_BUNDLE_ID" 2>/dev/null || true); do
  [[ "$pid" == "$SELF_PID" ]] && continue
  sudo kill -9 "$pid" 2>/dev/null && echo "  killed dext PID $pid" || true
done

# Catch anything else with "openjoystick" in the command line (exclude self)
for pid in $(pgrep -if "openjoystick" 2>/dev/null || true); do
  [[ "$pid" == "$SELF_PID" ]] && continue
  kill -9 "$pid" 2>/dev/null && echo "  killed stray PID $pid" || true
  sudo kill -9 "$pid" 2>/dev/null || true
done

echo ""
echo "=== NUKE: removing daemon from launchd ==="

# Prefer SMAppService uninstall (modern path). This avoids relying on `launchctl bootstrap`
# behavior and cleans up the registered agent cleanly.
if [[ -x "$APP_PATH/Contents/MacOS/OpenJoystickDriver" ]]; then
  "$APP_PATH/Contents/MacOS/OpenJoystickDriver" --headless uninstall \
    && echo "  SMAppService uninstall succeeded" || true
fi

# Unload via every method launchd supports
launchctl bootout "gui/$(id -u)/$DAEMON_LABEL" 2>/dev/null && echo "  bootout succeeded" || true
launchctl remove "$DAEMON_LABEL" 2>/dev/null && echo "  remove succeeded" || true
launchctl unload ~/Library/LaunchAgents/${DAEMON_LABEL}.plist 2>/dev/null && echo "  unload succeeded" || true

echo ""
echo "=== NUKE: removing LaunchAgent plist ==="
rm -f ~/Library/LaunchAgents/${DAEMON_LABEL}.plist && echo "  removed" || true

echo ""
echo "=== NUKE: removing app from /Applications ==="
if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH" 2>/dev/null || sudo rm -rf "$APP_PATH"
  echo "  removed $APP_PATH"
else
  echo "  (not present)"
fi

echo ""
echo "=== NUKE: truncating daemon logs ==="
: > /tmp/${DAEMON_LABEL}.out 2>/dev/null || true
: > /tmp/${DAEMON_LABEL}.err 2>/dev/null || true
echo "  truncated"

echo ""
echo "=== NUKE: clearing build artifacts ==="
rm -rf "$SCRIPT_DIR/../.build/dext" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/../.build/debug/OpenJoystickDriver.app" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/../.build/arm64-apple-macosx" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/../.build/x86_64-apple-macosx" 2>/dev/null || true
echo "  cleared .build/dext and .build/debug app"

echo ""
echo "=== NUKE: clearing Xcode derived data for dext ==="
rm -rf ~/Library/Developer/Xcode/DerivedData/OpenJoystickVirtualHID-* 2>/dev/null || true
echo "  cleared"

echo ""
echo "=== NUKE: verification ==="

STRAY=$(pgrep -if "openjoystick" 2>/dev/null | grep -v "^${SELF_PID}$" || true)
if [[ -z "$STRAY" ]]; then
  echo "  ✓ No OJD processes running"
else
  echo "  ✗ Still running: $STRAY"
fi

if launchctl list 2>/dev/null | grep -q "$DAEMON_LABEL"; then
  echo "  ✗ Daemon still in launchd"
else
  echo "  ✓ Daemon not in launchd"
fi

if [[ -d "$APP_PATH" ]]; then
  echo "  ✗ App still in /Applications"
else
  echo "  ✓ App not in /Applications"
fi

echo ""
echo "=== Sysext status (cannot remove with SIP — will be replaced on next install) ==="
systemextensionsctl list 2>&1 | grep openjoystick || echo "  (none)"

echo ""
echo "System is clean. Run ./scripts/rebuild.sh to deploy fresh."
