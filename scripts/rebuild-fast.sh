#!/usr/bin/env bash
# Fast rebuild during iteration (no sysext upgrade):
# - builds + signs GUI + daemon
# - preserves the existing embedded system extension in /Applications
# - restarts the daemon
#
# Use this while streaming / when you cannot reboot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

APP_DST="/Applications/OpenJoystickDriver.app"
APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

if [[ ! -d "$APP_DST" ]]; then
  echo "ERROR: $APP_DST not found."
  echo "Fix: run ./scripts/rebuild.sh once to install the system extension."
  exit 1
fi

echo "=== Step 1: Build app (no dext) ==="
"$SCRIPT_DIR/build-dev.sh"

echo ""
echo "=== Step 2: Preserve embedded system extension ==="
DEXT_DIR_DST="$APP_DST/Contents/Library/SystemExtensions"
DEXT_DIR_SRC="$APP_SRC/Contents/Library/SystemExtensions"

if [[ -d "$DEXT_DIR_DST" ]]; then
  mkdir -p "$DEXT_DIR_SRC"
  rm -rf "$DEXT_DIR_SRC"
  mkdir -p "$DEXT_DIR_SRC"
  cp -R "$DEXT_DIR_DST/"* "$DEXT_DIR_SRC/" 2>/dev/null || true
  echo "  Preserved: $DEXT_DIR_DST"
else
  echo "  WARN: No SystemExtensions folder in $APP_DST (sysext may not be installed yet)"
fi

echo ""
echo "=== Step 3: Install app (without triggering sysext upgrade) ==="
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
echo "  Copied to $APP_DST"

echo ""
echo "=== Step 4: Restart daemon ==="
: > /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || true
: > /tmp/com.openjoystickdriver.daemon.err 2>/dev/null || true

DAEMON_PLIST=~/Library/LaunchAgents/com.openjoystickdriver.daemon.plist
DAEMON_BIN_PATH="$APP_DST/Contents/MacOS/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
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

launchctl bootstrap "gui/$(id -u)" "$DAEMON_PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$DAEMON_LABEL" 2>/dev/null \
  && echo "  ✓ Daemon restarted" \
  || echo "  ⚠ Daemon kickstart failed"

echo ""
echo "=== Step 5: Launch app ==="
open "$APP_DST" || true
echo "  Launched OpenJoystickDriver"

echo ""
echo "Tip: If DriverKit injection is aborting during sysext replacement, switch to:"
echo "     Permissions → Output routing → User-space"

