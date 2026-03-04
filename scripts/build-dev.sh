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

echo "Signing GUI..."
ojd_sign "$GUI_DEBUG"

echo ""
echo "Signed with: $IDENTITY"
echo "  Daemon: $DAEMON_DEBUG"
echo "  GUI:    $GUI_DEBUG"
echo ""
if [[ "$IDENTITY" == "-" ]]; then
  echo "Note: ad-hoc signed. On Darwin 25+ (macOS 26), sudo may not be enough"
  echo "  for USB class 0xFF access. Set CODESIGN_IDENTITY to your Apple"
  echo "  Development cert to have USB entitlement enforced properly."
  echo "  Find it: security find-identity -v -p codesigning"
  echo ""
fi
echo "Run daemon:  sudo $DAEMON_DEBUG"
echo "Run GUI:     $GUI_DEBUG"
