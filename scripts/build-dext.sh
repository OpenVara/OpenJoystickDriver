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
DEXT_BUNDLE_VERSION="${DEXT_BUNDLE_VERSION:-}"

# ---------------------------------------------------------------------------
# Step 1: Validate signing requirements
# ---------------------------------------------------------------------------
if [[ "${CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "ERROR: DriverKit extensions cannot use ad-hoc signing."
    echo ""
    echo "You must set CODESIGN_IDENTITY to your Apple Development certificate."
    echo "Tip: run ./scripts/configure-signing.sh to auto-generate scripts/.env.dev"
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

resolve_xcodebuild_identity() {
  local id="$1"
  # Prefer passing the SHA1 identity straight through to xcodebuild.
  # This avoids name-based matching (which can accidentally pick a revoked cert
  # when multiple "Apple Development: …" certs exist in Keychain).
  if [[ "$id" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo "$id"
    return 0
  fi

  # If we're given a full Apple Development display name, do NOT forward it to xcodebuild.
  # Use the generic selector so Xcode picks the right cert for the team/profile.
  if [[ "$id" == Apple\ Development:* ]]; then
    echo "Apple Development"
    return 0
  fi

  echo "$id"
}

DEXT_BUILD_IDENTITY_XCODE="$(resolve_xcodebuild_identity "$DEXT_BUILD_IDENTITY")"
FINAL_IDENTITY_XCODE="$(resolve_xcodebuild_identity "$CODESIGN_IDENTITY")"

echo "Building DriverKit extension..."
echo "  Build identity: $DEXT_BUILD_IDENTITY_XCODE"
echo "  Build profile:  $DEXT_BUILD_PROFILE"
echo "  Final identity: $FINAL_IDENTITY_XCODE"
echo "  Team: $DEVELOPMENT_TEAM"

# ---------------------------------------------------------------------------
# Preflight: the DEXT profile must embed a cert that exists as a Keychain identity
# ---------------------------------------------------------------------------
DEXT_PROFILE_PATH="${DEXT_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
if [[ -f "$DEXT_PROFILE_PATH" ]]; then
  read -r PROFILE_EMBEDDED_SHA1 PROFILE_TEAM CERT_OU < <(
    python3 - "$DEXT_PROFILE_PATH" <<'PY' 2>/dev/null || true
import plistlib, subprocess, sys, tempfile, os
profile = sys.argv[1]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return p.stdout if (p.returncode == 0 and p.stdout) else b""

raw = decode(profile)
if not raw or b"<?xml" not in raw:
    raise SystemExit(0)
raw = raw[raw.index(b"<?xml") :]
obj = plistlib.loads(raw)

team = ""
ti = obj.get("TeamIdentifier") or []
if isinstance(ti, list) and ti:
    team = str(ti[0])

certs = obj.get("DeveloperCertificates") or []
sha = ""
ou = ""
if certs:
    der = certs[0]
    fp = subprocess.run(
        ["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"],
        input=der,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout.strip()
    if "=" in fp:
        sha = fp.split("=",1)[1].replace(":","").lower()

    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der)
        tmp = f.name
    try:
        subj = subprocess.run(["openssl","x509","-inform","DER","-in",tmp,"-noout","-subject","-nameopt","RFC2253"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
        if "OU=" in subj:
            ou = subj.split("OU=",1)[1].split(",",1)[0]
    finally:
        try: os.unlink(tmp)
        except OSError: pass

print(sha, team, ou)
PY
  ) || true

  # Only enforce this when `security find-identity` is usable (GUI session).
  KEYCHAIN_SHA1S="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\"Apple Development:/{print tolower($2)}' | tr '\n' ' ')"
  if [[ -n "${PROFILE_EMBEDDED_SHA1:-}" && -n "${KEYCHAIN_SHA1S// /}" ]]; then
    if ! echo " $KEYCHAIN_SHA1S " | grep -q " ${PROFILE_EMBEDDED_SHA1} "; then
      echo ""
      echo "ERROR: DEXT provisioning profile does not match your Keychain Apple Development certificate."
      echo "  DEXT profile: $DEXT_PROFILE_PATH"
      echo "  profile_team: ${PROFILE_TEAM:-UNKNOWN}"
      echo "  profile_embedded_cert_sha1: ${PROFILE_EMBEDDED_SHA1}"
      echo "  keychain_apple_development_sha1s: ${KEYCHAIN_SHA1S:-UNKNOWN}"
      echo ""
      echo "Fix (no guessing):"
      echo "  1) In Apple Developer portal, regenerate the DEXT provisioning profile"
      echo "     selecting the Apple Development certificate you actually have in Keychain."
      echo "  2) Reinstall it: ./scripts/install-profiles.sh \"$HOME/Documents/Profiles\""
      echo "  3) Re-run: ./scripts/configure-signing.sh"
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Preflight: profile team must match cert team
# ---------------------------------------------------------------------------
if [[ -f "$DEXT_PROFILE_PATH" ]]; then
  read -r PROFILE_TEAM CERT_OU < <(
    python3 - "$DEXT_PROFILE_PATH" <<'PY' 2>/dev/null || true
import plistlib, subprocess, sys, tempfile, os
profile = sys.argv[1]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return p.stdout if (p.returncode == 0 and p.stdout) else b""

raw = decode(profile)
if not raw or b"<?xml" not in raw:
    raise SystemExit(0)
raw = raw[raw.index(b"<?xml") :]
obj = plistlib.loads(raw)
team = ""
ti = obj.get("TeamIdentifier") or []
if isinstance(ti, list) and ti:
    team = str(ti[0])

certs = obj.get("DeveloperCertificates") or []
ou = ""
if certs:
    der = certs[0]
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der)
        tmp = f.name
    try:
        subj = subprocess.run(["openssl","x509","-inform","DER","-in",tmp,"-noout","-subject","-nameopt","RFC2253"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        s = subj.stdout.strip()
        # Extract OU=... from RFC2253 subject.
        if "OU=" in s:
            ou = s.split("OU=", 1)[1].split(",", 1)[0]
    finally:
        try: os.unlink(tmp)
        except OSError: pass

print(team, ou)
PY
  ) || true

  if [[ -n "${PROFILE_TEAM:-}" && -n "${CERT_OU:-}" && "$PROFILE_TEAM" != "$CERT_OU" ]]; then
    echo ""
    echo "ERROR: Signing team mismatch for DriverKit extension."
    echo "  DEXT provisioning profile team: $PROFILE_TEAM"
    echo "  Apple Development certificate team: $CERT_OU"
    echo ""
    echo "Fix (no guessing):"
    echo "  1) Create/download an Apple Development certificate for team $PROFILE_TEAM, OR"
    echo "  2) Regenerate the DEXT provisioning profile for team $CERT_OU and reinstall it."
    echo ""
    echo "Then re-run: ./scripts/build-dext.sh"
    exit 1
  fi
fi

# Ensure Xcode toolchain compilers are used even if Homebrew LLVM is earlier in PATH.
# Some Xcode build invocations call `clang` by basename; if PATH resolves to a
# non-Apple clang, the build can fail (e.g. unknown `-index-store-path`).
#
# This script is intentionally aggressive about PATH because the failure mode is
# confusing: xcodebuild prints `clang ...` and you only see a cryptic
# "unknown argument: -index-store-path" error.
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
XCODE_CLANG="$(xcrun --find clang)"
XCODE_CLANGXX="$(xcrun --find clang++ 2>/dev/null || true)"
if [[ -z "$XCODE_CLANGXX" ]]; then
  XCODE_CLANGXX="$(dirname "$XCODE_CLANG")/clang++"
fi
export PATH="$(dirname "$XCODE_CLANG"):/usr/bin:/bin:/usr/sbin:/sbin"
echo "  Compiler: $("$XCODE_CLANG" --version | head -n 1)"

# Xcode passes an index store path; create it proactively to avoid spurious
# "no such file or directory" errors if the build tooling doesn't create it.
mkdir -p "$DEXT_BUILD_DIR/Index.noindex/DataStore"

# Always clean build — stale .iig stubs cause vtable mismatches that
# produce kIOReturnNotPermitted (0xe00002eb) on setReport at runtime.
xcodebuild \
    -project "$DEXT_PROJECT" \
    -scheme "$DEXT_SCHEME" \
    -configuration "$DEXT_CONFIG" \
    -derivedDataPath "$DEXT_BUILD_DIR" \
    CC="$XCODE_CLANG" \
    CXX="$XCODE_CLANGXX" \
    CODE_SIGN_IDENTITY="$DEXT_BUILD_IDENTITY_XCODE" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PROVISIONING_PROFILE_SPECIFIER="$DEXT_BUILD_PROFILE" \
    CODE_SIGN_STYLE=Manual \
    clean build

if [[ ! -d "$DEXT_PRODUCT" ]]; then
    echo "ERROR: .dext not found at expected path: $DEXT_PRODUCT"
    exit 1
fi

if [[ -n "$DEXT_BUNDLE_VERSION" ]]; then
    # IMPORTANT:
    # System extensions are versioned. During development, macOS may refuse to
    # "upgrade" a sysext if CFBundleVersion does not increase.
    #
    # Do NOT bump DriverKitExtension/Info.plist in the repo (it dirties the tree).
    # Instead, bump the built product's Info.plist here and re-sign later when embedding.
    plutil -replace CFBundleVersion -string "$DEXT_BUNDLE_VERSION" "$DEXT_PRODUCT/Info.plist"
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

    # Copy to /Applications/ — sysextd requires the containing app to be in
    # /Applications/ for system extension discovery.
    #
    # During iteration (or in sandboxed environments), you may want to skip this step.
    if [[ "${OJD_SKIP_INSTALL:-0}" == "1" ]]; then
      echo "Skipping /Applications install (OJD_SKIP_INSTALL=1)"
    else
      echo "Installing to /Applications/OpenJoystickDriver.app..."
      rm -rf /Applications/OpenJoystickDriver.app
      cp -R "$GUI_APP" /Applications/
      echo "Copied to /Applications"
    fi
else
    echo "Note: GUI app bundle not found at $GUI_APP — build the main project first."
    echo "      Run ./scripts/build-dev.sh, then ./scripts/build-dext.sh again."
fi

echo ""
echo "DriverKit extension build complete."
echo "  .dext: $DEXT_PRODUCT"
