#!/usr/bin/env bash
# Unregisters daemon LaunchAgent and removes installed binaries.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Unregistering LaunchAgent..."
if command -v OpenJoystickDriver &>/dev/null; then
  OpenJoystickDriver --headless uninstall || true
fi

echo "Removing binaries from $INSTALL_DIR..."
sudo rm -f "$INSTALL_DIR/OpenJoystickDriverDaemon"
sudo rm -f "$INSTALL_DIR/OpenJoystickDriver"

echo ""
echo "OpenJoystickDriver uninstalled."
