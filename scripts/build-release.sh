#!/usr/bin/env bash
# Publisher release script - builds signed universal binary and notarizes it.
#
# REQUIREMENTS (publisher only - contributors use scripts/sign-dev.sh instead):
#   1. Valid Apple Developer account with Developer ID Application certificate.
#   2. Copy .env.example to .env and fill in all four values.
#   3. Developer ID Application certificate must be installed in your Keychain.
#
# USAGE:
#   ./scripts/build-release.sh
#
set -euo pipefail

# Force release environment so lib.sh loads .env.release
export OJD_ENV="release"
source "$(dirname "$0")/lib.sh"

DAEMON_ENTITLEMENTS_RELEASE="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"

: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY not set in .env.release}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID not set in .env.release}"
: "${APPLE_ID:?APPLE_ID not set in .env.release}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD not set in .env.release}"

echo "Running lint checks..."
cd "$PROJECT_DIR"
swiftlint lint --strict

setup_libusb_pkgconfig

echo "Building universal binaries..."
swift build -c release --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64
swift build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64

RELEASE="$PROJECT_DIR/.build/apple/Products/Release"
DAEMON="$RELEASE/OpenJoystickDriverDaemon"
GUI="$RELEASE/OpenJoystickDriver"

echo "Signing daemon (USB entitlements + hardened runtime)..."
codesign \
  --sign "$CODESIGN_IDENTITY" \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$DAEMON_ENTITLEMENTS_RELEASE" \
  "$DAEMON"

echo "Signing GUI (hardened runtime + system-extension entitlement)..."
GUI_ENTITLEMENTS_RELEASE="$PROJECT_DIR/Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements"
codesign \
  --sign "$CODESIGN_IDENTITY" \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$GUI_ENTITLEMENTS_RELEASE" \
  "$GUI"

echo "Verifying signatures..."
codesign --verify --deep --strict "$DAEMON"
codesign --verify --deep --strict "$GUI"
codesign --display --verbose=4 "$DAEMON" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier"

# Apple requires notarization for Gatekeeper to accept Developer ID-signed
# binaries on other Macs without security prompt. Tickets are verified online;
# stapling is not supported for raw executables (only .app/.pkg/.dmg).
notarize() {
  local binary="$1"
  local name
  name="$(basename "$binary")"
  local zipfile="$RELEASE/$name.zip"

  echo "Notarizing $name..."
  zip -j "$zipfile" "$binary"
  xcrun notarytool submit "$zipfile" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  rm "$zipfile"
  echo "Notarized: $binary"
}

notarize "$DAEMON"
notarize "$GUI"

echo ""
echo "Release build complete."
echo "  Daemon: $DAEMON"
echo "  GUI:    $GUI"
echo ""
echo "Next steps:"
echo "  • Run scripts/install.sh to install locally, or"
echo "  • Package into .dmg / Homebrew formula for distribution."
