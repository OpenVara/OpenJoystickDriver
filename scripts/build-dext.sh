#!/usr/bin/env bash
# Build the OJD DriverKit virtual HID extension and embed it in the app bundle.
#
# IMPORTANT: DriverKit extensions CANNOT use ad-hoc signing. You MUST have:
#   1. Apple Developer Program membership
#   2. A provisioning profile with DriverKit entitlements
#   3. CODESIGN_IDENTITY set to your Apple Development certificate
#   4. DEVELOPMENT_TEAM set to your team ID
#   5. PROVISIONING_PROFILE_SPECIFIER set to your provisioning profile name
#
# To request DriverKit entitlements:
#   https://developer.apple.com/contact/request/system-extension
#
# USAGE:
#   CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
#   DEVELOPMENT_TEAM="ABCDEF1234" \
#   PROVISIONING_PROFILE_SPECIFIER="OpenJoystickDriver DriverKit Dev" \
#   ./scripts/build-dext.sh
#
# OUTPUT:
#   .build/dext/Build/Products/Debug/OpenJoystickVirtualHID.dext
#   Embedded into .build/debug/OpenJoystickDriver.app if it exists.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DEXT_DIR="$PROJECT_DIR/DriverKitExtension"
DEXT_PROJECT="$DEXT_DIR/OpenJoystickVirtualHID.xcodeproj"
DEXT_SCHEME="OpenJoystickVirtualHID"
DEXT_BUILD_DIR="$PROJECT_DIR/.build/dext"
DEXT_PRODUCT="$DEXT_BUILD_DIR/Build/Products/Debug/OpenJoystickVirtualHID.dext"

# ---------------------------------------------------------------------------
# Step 1: Validate signing requirements
# ---------------------------------------------------------------------------
if [[ "${CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "ERROR: DriverKit extensions cannot use ad-hoc signing."
    echo ""
    echo "You must set CODESIGN_IDENTITY to your Apple Development certificate."
    echo "Find your signing identity:"
    echo "  security find-identity -v -p codesigning"
    echo ""
    echo "You also need DEVELOPMENT_TEAM and PROVISIONING_PROFILE_SPECIFIER."
    echo "See script header for details."
    exit 1
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM not set."
    echo "Set it to your Apple Developer Team ID (e.g., ABCDEF1234)."
    exit 1
fi

if [[ ! -d "$DEXT_PROJECT" ]]; then
    echo "ERROR: Xcode project not found at $DEXT_PROJECT"
    echo "The project.pbxproj should already exist in the repository."
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Build with xcodebuild
# ---------------------------------------------------------------------------
echo "Building DriverKit extension..."
echo "  Identity: $CODESIGN_IDENTITY"
echo "  Team: $DEVELOPMENT_TEAM"
echo "  Profile: ${PROVISIONING_PROFILE_SPECIFIER:-<not set>}"
xcodebuild \
    -project "$DEXT_PROJECT" \
    -scheme "$DEXT_SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DEXT_BUILD_DIR" \
    CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-}" \
    CODE_SIGN_STYLE=Manual \
    build

if [[ ! -d "$DEXT_PRODUCT" ]]; then
    echo "ERROR: .dext not found at expected path: $DEXT_PRODUCT"
    exit 1
fi

echo "Built: $DEXT_PRODUCT"

# ---------------------------------------------------------------------------
# Step 3: Embed .dext into the GUI app bundle (if the app is already built)
# ---------------------------------------------------------------------------
# SPM builds the GUI as a plain executable; for dext embedding we need an
# app bundle wrapper. Check if one exists (created by build-dev.sh or Xcode).
GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
DEXT_DEST="$GUI_APP/Contents/Library/SystemExtensions"

if [[ -d "$GUI_APP" ]]; then
    echo "Embedding dext into app bundle..."
    mkdir -p "$DEXT_DEST"
    rm -rf "$DEXT_DEST/OpenJoystickVirtualHID.dext"
    cp -R "$DEXT_PRODUCT" "$DEXT_DEST/"
    echo "Embedded at: $DEXT_DEST/OpenJoystickVirtualHID.dext"
else
    echo "Note: GUI app bundle not found at $GUI_APP — build the main project first."
    echo "      Run ./scripts/build-dev.sh, then ./scripts/build-dext.sh again."
fi

echo ""
echo "DriverKit extension build complete."
echo "  .dext: $DEXT_PRODUCT"
