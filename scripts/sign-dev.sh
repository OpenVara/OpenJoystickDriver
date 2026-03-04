#!/usr/bin/env bash
# Development signing script - no Apple Developer account required.
#
# Uses ad-hoc signing (-) which satisfies macOS Hardened Runtime for local use.
# Ad-hoc signing does NOT grant USB Device entitlement, so daemon
# must still run as root (sudo) to access class 0xFF USB devices.
#
# USAGE:
#   ./scripts/sign-dev.sh
#
# To run daemon after signing:
#   sudo .build/debug/OpenJoystickDriverDaemon
#
set -euo pipefail
cd "$(dirname "$0")/.."

ENTITLEMENTS="Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"

echo "Building debug binaries..."
swift build --product OpenJoystickDriverDaemon
swift build --product OpenJoystickDriver

DAEMON=".build/debug/OpenJoystickDriverDaemon"
GUI=".build/debug/OpenJoystickDriver"

# Ad-hoc signing without --options runtime: hardened runtime enforces library
# validation and rejects Homebrew dylibs (different Team ID). Dev builds don't
# need hardened runtime — that's notarization requirement only.
echo "Ad-hoc signing daemon (with entitlements)..."
codesign --sign - --force \
  --entitlements "$ENTITLEMENTS" \
  "$DAEMON"

echo "Ad-hoc signing GUI..."
codesign --sign - --force "$GUI"

echo ""
echo "Signed (ad-hoc):"
echo "  Daemon: $DAEMON"
echo "  GUI:    $GUI"
echo ""
echo "Note: USB class 0xFF access still requires sudo with ad-hoc signing."
echo "  Run daemon:  sudo $DAEMON"
echo "  Run GUI:     $GUI"
