#!/usr/bin/env bash
# Build, kill running instances, deploy new binaries, and restart everything.
# Use this for fast iteration when the LaunchAgent is already installed.
#
# Requires the LaunchAgent to be registered first (scripts/install.sh).
# Uses debug build for speed; signs with CODESIGN_IDENTITY if set.
#
# USAGE:
#   ./scripts/redeploy.sh
#   CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/redeploy.sh
#   INSTALL_DIR=/usr/local/bin ./scripts/redeploy.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
INSTALLED_DAEMON="$INSTALL_DIR/OpenJoystickDriverDaemon"
INSTALLED_GUI="$INSTALL_DIR/OpenJoystickDriver"

echo "Stopping running processes..."
# Kill GUI app first so it releases any IPC connections to the daemon.
pkill -x OpenJoystickDriver 2>/dev/null || true
# Kill any directly-running daemon (non-launchd, e.g. via run-dev.sh with sudo).
pkill -x OpenJoystickDriverDaemon 2>/dev/null || true
sudo pkill -x OpenJoystickDriverDaemon 2>/dev/null || true

echo "Building debug binaries..."
cd "$PROJECT_DIR"
swift build --product OpenJoystickDriverDaemon
swift build --product OpenJoystickDriver

echo "Signing daemon using: $IDENTITY"
ojd_sign "$DAEMON_DEBUG" --entitlements "$ENTITLEMENTS"

echo "Signing GUI..."
ojd_sign "$GUI_DEBUG"

echo "Deploying to $INSTALL_DIR..."
sudo install -m 755 "$DAEMON_DEBUG" "$INSTALLED_DAEMON"
sudo install -m 755 "$GUI_DEBUG" "$INSTALLED_GUI"

echo "Restarting daemon..."
"$INSTALLED_GUI" --headless restart

echo "Launching GUI..."
"$INSTALLED_GUI" &
disown

echo ""
echo "Done. Both binaries replaced and restarted."
echo "  Daemon: $INSTALLED_DAEMON"
echo "  GUI:    $INSTALLED_GUI"
