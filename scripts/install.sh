#!/usr/bin/env bash
# Builds native binary, installs to INSTALL_DIR,
# and registers daemon as LaunchAgent for current user.
# For signed universal binary (distribution), use scripts/build-release.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Building..."
cd "$PROJECT_DIR"
swift build -c release --product OpenJoystickDriverDaemon
swift build -c release --product OpenJoystickDriver

RELEASE=".build/release"

echo "Installing to $INSTALL_DIR..."
sudo install -m 755 "$RELEASE/OpenJoystickDriverDaemon" \
  "$INSTALL_DIR/OpenJoystickDriverDaemon"
sudo install -m 755 "$RELEASE/OpenJoystickDriver" \
  "$INSTALL_DIR/OpenJoystickDriver"

echo "Registering LaunchAgent..."
"$INSTALL_DIR/OpenJoystickDriver" --headless install

echo ""
echo "OpenJoystickDriver installed successfully."
echo "  Daemon:  $INSTALL_DIR/OpenJoystickDriverDaemon"
echo "  GUI:     $INSTALL_DIR/OpenJoystickDriver"
echo "  Service: com.openjoystickdriver.daemon (auto-starts on login)"
