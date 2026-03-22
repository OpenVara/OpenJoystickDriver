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
if [[ "$OJD_ENV" == "release" ]]; then
  DEXT_CONFIG="Release"
else
  DEXT_CONFIG="Debug"
fi
DEXT_PRODUCT="$DEXT_BUILD_DIR/Build/Products/${DEXT_CONFIG}-driverkit/OpenJoystickVirtualHID.dext"

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
# DriverKit xcodebuild requires an Apple Development identity + a dev profile
# with both iOS and macOS platforms. The dext is re-signed with the final
# identity (e.g. Developer ID) after embedding into the app bundle.
# DriverKit xcodebuild always requires an Apple Development identity + profile.
# For dev builds, CODESIGN_IDENTITY is already Apple Development.
# For release builds, override DEXT_BUILD_IDENTITY in .env.release if different.
DEXT_BUILD_IDENTITY="${DEXT_BUILD_IDENTITY:-$CODESIGN_IDENTITY}"
DEXT_BUILD_PROFILE="${DEXT_BUILD_PROFILE:-OpenJoystickDriver (VirtualHIDDevice)}"

echo "Building DriverKit extension..."
echo "  Build identity: $DEXT_BUILD_IDENTITY"
echo "  Build profile:  $DEXT_BUILD_PROFILE"
echo "  Final identity: $CODESIGN_IDENTITY"
echo "  Team: $DEVELOPMENT_TEAM"
# Always clean build — stale .iig stubs cause vtable mismatches that
# produce kIOReturnNotPermitted (0xe00002eb) on setReport at runtime.
xcodebuild \
    -project "$DEXT_PROJECT" \
    -scheme "$DEXT_SCHEME" \
    -configuration "$DEXT_CONFIG" \
    -derivedDataPath "$DEXT_BUILD_DIR" \
    CODE_SIGN_IDENTITY="$DEXT_BUILD_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PROVISIONING_PROFILE_SPECIFIER="$DEXT_BUILD_PROFILE" \
    CODE_SIGN_STYLE=Manual \
    HEADER_SEARCH_PATHS='$(inherited) $(SRCROOT)/../Shared/CGamepadDescriptor/include' \
    clean build

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
DEXT_SYSEXT="$GUI_APP/Contents/Library/SystemExtensions"

# OSSystemExtensionManager looks up extensions by bundle-ID-based filename,
# e.g. "com.openjoystickdriver.VirtualHIDDevice.dext" — not the product name.
DEXT_BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$DEXT_PRODUCT/Info.plist")
DEXT_FILENAME="${DEXT_BUNDLE_ID}.dext"

if [[ -d "$GUI_APP" ]]; then
    echo "Embedding dext into app bundle..."
    echo "  Dext bundle ID: $DEXT_BUNDLE_ID"
    echo "  Dext filename:  $DEXT_FILENAME"

    # Place in Library/SystemExtensions/ named by bundle ID —
    # this is where OSSystemExtensionManager discovers extensions
    mkdir -p "$DEXT_SYSEXT"
    rm -rf "$DEXT_SYSEXT/$DEXT_FILENAME"
    rm -rf "$DEXT_SYSEXT/OpenJoystickVirtualHID.dext"  # clean up old name
    cp -R "$DEXT_PRODUCT" "$DEXT_SYSEXT/$DEXT_FILENAME"

    # Flat bundles without CFBundleExecutable use the directory name (minus .dext)
    # as the executable name. Since we renamed the directory to the bundle ID,
    # we must add CFBundleExecutable pointing to the actual binary.
    DEXT_EXEC_NAME=$(ls "$DEXT_SYSEXT/$DEXT_FILENAME/" | grep -v -E 'Info\.plist|_CodeSignature|embedded\.provisionprofile')

    # Ensure dext binary is executable — xcodebuild may produce 644 for
    # DriverKit targets, causing launchd to reject with "Permission denied"
    chmod +x "$DEXT_SYSEXT/$DEXT_FILENAME/$DEXT_EXEC_NAME"
    plutil -replace CFBundleExecutable -string "$DEXT_EXEC_NAME" \
        "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist" 2>/dev/null \
      || plutil -insert CFBundleExecutable -string "$DEXT_EXEC_NAME" \
          "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist"

    # Extract original entitlements before re-signing (xcodebuild applied
    # DriverKit entitlements from the provisioning profile)
    DEXT_ENTITLEMENTS_TMP="$PROJECT_DIR/.build/dext-entitlements.plist"
    if ! codesign -d --entitlements - --xml "$DEXT_SYSEXT/$DEXT_FILENAME" > "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null; then
      echo "ERROR: Failed to extract entitlements from dext — codesign may have stripped them"
      exit 1
    fi

    # For release builds, strip debug entitlements that block notarization
    # (PlistBuddy required because plutil treats dots as key path separators)
    if [[ "$OJD_ENV" == "release" ]]; then
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Delete :get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
    fi

    # Re-sign the dext after modifying Info.plist, preserving entitlements
    DEXT_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der
        --entitlements "$DEXT_ENTITLEMENTS_TMP")
    if [[ "$OJD_ENV" == "release" ]]; then
      DEXT_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${DEXT_SIGN_ARGS[@]}" "$DEXT_SYSEXT/$DEXT_FILENAME"

    echo "Embedded at: $DEXT_SYSEXT/$DEXT_FILENAME (exec: $DEXT_EXEC_NAME)"

    # Resolve entitlements if not already done by build-dev.sh
    if [[ ! -f "$GUI_ENTITLEMENTS" ]]; then
      mkdir -p "$PROJECT_DIR/.build"
      resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
    fi

    # Re-sign outer app. The dext in PlugIns/ is sealed as nested code.
    # The dext in Library/SystemExtensions/ is sealed as opaque data but
    # retains its own independent signature for OSSystemExtensionManager.
    echo "Re-signing app bundle..."
    APP_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der
        --entitlements "$GUI_ENTITLEMENTS")
    if [[ "$OJD_ENV" == "release" ]]; then
      APP_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${APP_SIGN_ARGS[@]}" "$GUI_APP"

    # Always copy to /Applications/ — sysextd requires the containing app
    # to be in /Applications/ for system extension discovery
    echo "Installing to /Applications/OpenJoystickDriver.app..."
    rm -rf /Applications/OpenJoystickDriver.app
    cp -R "$GUI_APP" /Applications/
    echo "Copied to /Applications"
else
    echo "Note: GUI app bundle not found at $GUI_APP — build the main project first."
    echo "      Run ./scripts/build-dev.sh, then ./scripts/build-dext.sh again."
fi

echo ""
echo "DriverKit extension build complete."
echo "  .dext: $DEXT_PRODUCT"
