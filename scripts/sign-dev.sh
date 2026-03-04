#!/usr/bin/env bash
# Development signing script.
#
# SIGNING MODES:
#
#   Ad-hoc (default, no Apple account needed):
#     Embeds entitlements in binary but macOS does NOT enforce them.
#     On Darwin 25+ (macOS 26+), sudo alone is insufficient for USB class 0xFF
#     access - IOKit now requires com.apple.security.device.usb to be honored,
#     which only happens with real signing identity.
#
#   Apple Development (recommended):
#     Signs with your Apple Development certificate (free Apple Account via Xcode).
#     Entitlements are enforced - USB access works without sudo.
#     Set CODESIGN_IDENTITY before running:
#       export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#       ./scripts/sign-dev.sh
#     Find your identity: security find-identity -v -p codesigning
#
# USAGE:
#   ./scripts/sign-dev.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENTITLEMENTS="Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"
# Use CODESIGN_IDENTITY env var if set, otherwise fall back to ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "Building debug binaries..."
swift build --product OpenJoystickDriverDaemon
swift build --product OpenJoystickDriver

DAEMON=".build/debug/OpenJoystickDriverDaemon"
GUI=".build/debug/OpenJoystickDriver"

# No --options runtime: hardened runtime enforces library validation and rejects
# Homebrew dylibs (different Team ID). Dev builds don't need hardened runtime.
echo "Signing daemon (with entitlements) using: $IDENTITY"
codesign --sign "$IDENTITY" --force \
  --entitlements "$ENTITLEMENTS" \
  "$DAEMON"

echo "Signing GUI..."
codesign --sign "$IDENTITY" --force "$GUI"

echo ""
echo "Signed with: $IDENTITY"
echo "  Daemon: $DAEMON"
echo "  GUI:    $GUI"
echo ""
if [[ "$IDENTITY" == "-" ]]; then
  echo "Note: ad-hoc signed. On Darwin 25+ (macOS 16), sudo may not be enough"
  echo "  for USB class 0xFF access. Set CODESIGN_IDENTITY to your Apple"
  echo "  Development cert to have USB entitlement enforced properly."
  echo "  Find it: security find-identity -v -p codesigning"
  echo ""
fi
echo "Run daemon:  sudo $DAEMON"
echo "Run GUI:     $GUI"
