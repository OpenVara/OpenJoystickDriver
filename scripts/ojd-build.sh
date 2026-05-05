#!/usr/bin/env bash
# Consolidated build/rebuild script for OpenJoystickDriver.
#
# Human-facing entrypoint is: ./scripts/ojd
#
# This file exists so the repo does not devolve into 20+ half-overlapping scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

# zsh has a 'log' builtin that shadows /usr/bin/log — always use full path
LOG=/usr/bin/log

die() { echo "ERROR: $*" >&2; exit 2; }

usage() {
  cat <<'TXT'
Usage:
  ./scripts/ojd build dev
  ./scripts/ojd build release
  ./scripts/ojd build dext

  ./scripts/ojd rebuild dev
  ./scripts/ojd rebuild release
  ./scripts/ojd rebuild-fast dev

Notes:
  - Full rebuild upgrades the DriverKit system extension (may require reboot).
  - rebuild-fast preserves the already-installed sysext (safe while streaming).
TXT
}

_require_codesign_identity() {
  if [[ "${IDENTITY:-"-"}" == "-" ]]; then
    echo "ERROR: CODESIGN_IDENTITY not set."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Nuke (from scripts/nuke.sh)
# ---------------------------------------------------------------------------
nuke_all() {
  local SELF_PID=$$
  local DEXT_BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
  local DAEMON_LABEL="com.openjoystickdriver.daemon"
  local APP_PATH="/Applications/OpenJoystickDriver.app"

  echo "=== NUKE: killing every OJD process ==="
  killall -9 OpenJoystickDriver 2>/dev/null && echo "  killed OpenJoystickDriver" || true
  killall -9 OpenJoystickDriverDaemon 2>/dev/null && echo "  killed OpenJoystickDriverDaemon" || true
  killall -9 OpenJoystickVirtualHID 2>/dev/null && echo "  killed OpenJoystickVirtualHID" || true

  for pid in $(pgrep -f "$DEXT_BUNDLE_ID" 2>/dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    sudo kill -9 "$pid" 2>/dev/null && echo "  killed dext PID $pid" || true
  done

  for pid in $(pgrep -if "openjoystick" 2>/dev/null || true); do
    [[ "$pid" == "$SELF_PID" ]] && continue
    kill -9 "$pid" 2>/dev/null && echo "  killed stray PID $pid" || true
    sudo kill -9 "$pid" 2>/dev/null || true
  done

  echo ""
  echo "=== NUKE: removing daemon from launchd ==="
  if [[ -x "$APP_PATH/Contents/MacOS/OpenJoystickDriver" ]]; then
    "$APP_PATH/Contents/MacOS/OpenJoystickDriver" --headless uninstall \
      && echo "  SMAppService uninstall succeeded" || true
  fi
  launchctl bootout "gui/$(id -u)/$DAEMON_LABEL" 2>/dev/null && echo "  bootout succeeded" || true
  launchctl remove "$DAEMON_LABEL" 2>/dev/null && echo "  remove succeeded" || true
  launchctl unload ~/Library/LaunchAgents/${DAEMON_LABEL}.plist 2>/dev/null && echo "  unload succeeded" || true

  echo ""
  echo "=== NUKE: removing LaunchAgent plist ==="
  rm -f ~/Library/LaunchAgents/${DAEMON_LABEL}.plist && echo "  removed" || true

  echo ""
  echo "=== NUKE: removing app from /Applications ==="
  if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH" 2>/dev/null || sudo rm -rf "$APP_PATH"
    echo "  removed $APP_PATH"
  else
    echo "  (not present)"
  fi

  echo ""
  echo "=== NUKE: truncating daemon logs ==="
  : > /tmp/${DAEMON_LABEL}.out 2>/dev/null || true
  : > /tmp/${DAEMON_LABEL}.err 2>/dev/null || true
  echo "  truncated"

  echo ""
  echo "=== NUKE: clearing build artifacts ==="
  rm -rf "$SCRIPT_DIR/../.build/dext" 2>/dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/debug/OpenJoystickDriver.app" 2>/dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/arm64-apple-macosx" 2>/dev/null || true
  rm -rf "$SCRIPT_DIR/../.build/x86_64-apple-macosx" 2>/dev/null || true
  echo "  cleared .build/dext and .build/debug app"

  echo ""
  echo "=== NUKE: clearing Xcode derived data for dext ==="
  rm -rf ~/Library/Developer/Xcode/DerivedData/OpenJoystickVirtualHID-* 2>/dev/null || true
  echo "  cleared"

  echo ""
  echo "=== NUKE: verification ==="
  local STRAY
  STRAY=$(pgrep -if "openjoystick" 2>/dev/null | grep -v "^${SELF_PID}$" || true)
  if [[ -z "$STRAY" ]]; then
    echo "  ✓ No OJD processes running"
  else
    echo "  ✗ Still running: $STRAY"
  fi

  if launchctl list 2>/dev/null | grep -q "$DAEMON_LABEL"; then
    echo "  ✗ Daemon still in launchd"
  else
    echo "  ✓ Daemon not in launchd"
  fi

  if [[ -d "$APP_PATH" ]]; then
    echo "  ✗ App still in /Applications"
  else
    echo "  ✓ App not in /Applications"
  fi

  echo ""
  echo "=== Sysext status (cannot remove with SIP — will be replaced on next install) ==="
  systemextensionsctl list 2>&1 | grep openjoystick || echo "  (none)"
}

# ---------------------------------------------------------------------------
# Build app (from scripts/build-dev.sh)
# ---------------------------------------------------------------------------
_profile_has_entitlement() {
  local profile="$1" key="$2"
  python3 - "$profile" "$key" <<'PY'
import os, sys, plistlib, subprocess
profile, key = sys.argv[1], sys.argv[2]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if p.returncode == 0 and p.stdout:
        return p.stdout
    return b""

try:
    raw = decode(profile)
    if not raw:
        print("decode_error")
        raise SystemExit(0)
    if b"<?xml" not in raw:
        print("decode_error")
        raise SystemExit(0)
    raw = raw[raw.index(b"<?xml") :]
    obj = plistlib.loads(raw)
except Exception:
    print("decode_error")
    raise SystemExit(0)

ent = obj.get("Entitlements") or {}
print("true" if key in ent else "false")
PY
}

_require_profile_entitlement() {
  local profile="$1" key="$2" what="$3" fix="$4"
  local ok
  ok="$(_profile_has_entitlement "$profile" "$key" || echo "false")"
  if [[ "$ok" == "decode_error" ]]; then
    echo ""
    echo "ERROR: Could not decode provisioning profile to check entitlements."
    echo "  profile: $profile"
    echo ""
    echo "Fix:"
    echo "  1) Install profiles: ./scripts/ojd signing install-profiles"
    echo "  2) Audit profiles:   ./scripts/ojd signing audit"
    exit 1
  fi
  if [[ "$ok" != "true" ]]; then
    echo ""
    echo "ERROR: Provisioning profile is missing entitlement: $key"
    echo "  profile: $profile"
    echo "  affects: $what"
    echo ""
    echo "$fix"
    exit 1
  fi
}

build_app_bundle() {
  _require_codesign_identity

  for profile_var in DAEMON_PROFILE GUI_PROFILE; do
    profile_path="${!profile_var}"
    if [[ ! -f "$profile_path" ]]; then
      echo "ERROR: Provisioning profile not found: $profile_path"
      echo "Fix: run: ./scripts/ojd signing install-profiles"
      exit 1
    fi
  done

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.system-extension.install" \
    "GUI app (system extension install)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with the System Extension install capability, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$GUI_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "GUI app (Compatibility / embedded backend IOHIDUserDevice)" \
    "Fix: regenerate the GUI provisioning profile for Identifier com.openjoystickdriver with entitlement com.apple.developer.hid.virtual.device, then reinstall profiles (./scripts/ojd signing install-profiles)."

  _require_profile_entitlement \
    "$DAEMON_PROFILE" \
    "com.apple.developer.hid.virtual.device" \
    "Daemon (Compatibility IOHIDUserDevice)" \
    "Fix: enable entitlement com.apple.developer.hid.virtual.device on Identifier com.openjoystickdriver.daemon, regenerate the daemon provisioning profile, then reinstall profiles (./scripts/ojd signing install-profiles)."

  if [[ "$OJD_ENV" == "release" ]]; then
    setup_libusb_pkgconfig
  fi

  if [[ "$OJD_ENV" == "release" ]]; then
    echo "Building release binaries (universal)..."
    cd "$PROJECT_DIR"
    swift build -c release --product OpenJoystickDriverDaemon --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
    swift build -c release --product OpenJoystickDriver --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
  else
    echo "Building debug binaries..."
    cd "$PROJECT_DIR"
    swift build --product OpenJoystickDriverDaemon -Xswiftc -warnings-as-errors
    swift build --product OpenJoystickDriver -Xswiftc -warnings-as-errors
  fi

  mkdir -p "$PROJECT_DIR/.build"
  resolve_entitlements "$DAEMON_ENTITLEMENTS_TEMPLATE" "$DAEMON_ENTITLEMENTS"
  resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"

  local GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  local GUI_CONTENTS="$GUI_APP/Contents"
  local GUI_MACOS="$GUI_CONTENTS/MacOS"

  echo "Creating app bundle..."
  rm -rf "$GUI_APP"
  mkdir -p "$GUI_MACOS"
  cp "$GUI_BIN" "$GUI_MACOS/OpenJoystickDriver"
  cp "$DAEMON_BIN" "$GUI_MACOS/OpenJoystickDriverDaemon"

  local BUILD_DIR
  BUILD_DIR="$(dirname "$DAEMON_BIN")"
  local GUI_RESOURCES="$GUI_CONTENTS/Resources"
  mkdir -p "$GUI_RESOURCES"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$GUI_RESOURCES/"
  done

  local LAUNCHAGENTS_SRC="$PROJECT_DIR/Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
  local LAUNCHAGENTS_DST="$GUI_CONTENTS/Library/LaunchAgents"
  mkdir -p "$LAUNCHAGENTS_DST"
  cp "$LAUNCHAGENTS_SRC" "$LAUNCHAGENTS_DST/com.openjoystickdriver.daemon.plist"

  cp "$GUI_PROFILE" "$GUI_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$GUI_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

  cat > "$GUI_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleDisplayName</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSystemExtensionUsageDescription</key>
    <string>OpenJoystickDriver uses this extension to present physical controllers as a standard virtual HID gamepad to games and applications, without requiring Accessibility permission.</string>
</dict>
</plist>
PLIST

  local DAEMON_BUNDLE="$GUI_MACOS/OpenJoystickDriverDaemon.app"
  local DAEMON_BUNDLE_CONTENTS="$DAEMON_BUNDLE/Contents"
  local DAEMON_BUNDLE_MACOS="$DAEMON_BUNDLE_CONTENTS/MacOS"

  echo "Creating daemon bundle..."
  mkdir -p "$DAEMON_BUNDLE_MACOS"
  cp "$DAEMON_BIN" "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon"
  cp "$DAEMON_PROFILE" "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile"
  xattr -d com.apple.quarantine "$DAEMON_BUNDLE_CONTENTS/embedded.provisionprofile" 2>/dev/null || true

  local DAEMON_RESOURCES="$DAEMON_BUNDLE_CONTENTS/Resources"
  mkdir -p "$DAEMON_RESOURCES"
  for bundle in "$BUILD_DIR"/OpenJoystickDriver_*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$DAEMON_RESOURCES/"
  done

  cat > "$DAEMON_BUNDLE_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.openjoystickdriver.daemon</string>
    <key>CFBundleName</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundleExecutable</key>
    <string>OpenJoystickDriverDaemon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

  echo "Signing using: $IDENTITY"
  ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"
  ojd_sign "$GUI_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  ojd_sign "$GUI_APP" --entitlements "$GUI_ENTITLEMENTS"
  ojd_sign "$DAEMON_BUNDLE_MACOS/OpenJoystickDriverDaemon" --entitlements "$DAEMON_ENTITLEMENTS"
  ojd_sign "$DAEMON_BUNDLE" --entitlements "$DAEMON_ENTITLEMENTS"

  if [[ "$OJD_ENV" == "release" ]]; then
    verify_profile_cert "$GUI_PROFILE" "$IDENTITY"
    verify_profile_cert "$DAEMON_PROFILE" "$IDENTITY"
  fi

  echo ""
  echo "Signed with: $IDENTITY"
  echo "  GUI app:        $GUI_APP"
  echo "  Daemon bundle:  $DAEMON_BUNDLE"
}

# ---------------------------------------------------------------------------
# Build dext (from scripts/build-dext.sh)
# ---------------------------------------------------------------------------
build_dext_bundle() {
  if [[ "${CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "ERROR: DriverKit extensions cannot use ad-hoc signing."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM not set."
    echo "Fix: run: ./scripts/ojd signing configure"
    exit 1
  fi

  local DEXT_DIR="$PROJECT_DIR/DriverKitExtension"
  local DEXT_PROJECT="$DEXT_DIR/OpenJoystickVirtualHID.xcodeproj"
  local DEXT_SCHEME="OpenJoystickVirtualHID"
  local DEXT_BUILD_DIR="$PROJECT_DIR/.build/dext"
  local DEXT_CONFIG
  if [[ "$OJD_ENV" == "release" ]]; then
    DEXT_CONFIG="Release"
  else
    DEXT_CONFIG="Debug"
  fi
  local DEXT_PRODUCT="$DEXT_BUILD_DIR/Build/Products/${DEXT_CONFIG}-driverkit/OpenJoystickVirtualHID.dext"
  local DEXT_BUNDLE_VERSION="${DEXT_BUNDLE_VERSION:-}"

  local DEXT_BUILD_IDENTITY="${DEXT_BUILD_IDENTITY:-$CODESIGN_IDENTITY}"
  local DEXT_BUILD_PROFILE="${DEXT_BUILD_PROFILE:-OpenJoystickDriver (VirtualHIDDevice)}"

  resolve_xcodebuild_identity() {
    local id="$1"
    if [[ "$id" =~ ^[0-9A-Fa-f]{40}$ ]]; then
      echo "$id"
      return 0
    fi
    if [[ "$id" == Apple\ Development:* ]]; then
      echo "Apple Development"
      return 0
    fi
    echo "$id"
  }

  local DEXT_BUILD_IDENTITY_XCODE
  DEXT_BUILD_IDENTITY_XCODE="$(resolve_xcodebuild_identity "$DEXT_BUILD_IDENTITY")"

  echo "Building DriverKit extension..."
  echo "  Build identity: $DEXT_BUILD_IDENTITY_XCODE"
  echo "  Build profile:  $DEXT_BUILD_PROFILE"
  echo "  Team: $DEVELOPMENT_TEAM"

  local DEXT_PROFILE_PATH="${DEXT_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
  if [[ -f "$DEXT_PROFILE_PATH" ]]; then
    read -r PROFILE_EMBEDDED_SHA1 PROFILE_TEAM CERT_OU < <(
      python3 - "$DEXT_PROFILE_PATH" <<'PY' 2>/dev/null || true
import plistlib, subprocess, sys, tempfile, os
profile = sys.argv[1]
def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
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
    fp = subprocess.run(["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"],
        input=der, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
    if "=" in fp:
        sha = fp.split("=",1)[1].replace(":","").lower()
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der); tmp=f.name
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

    local KEYCHAIN_SHA1S
    KEYCHAIN_SHA1S="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\"Apple Development:/{print tolower($2)}' | tr '\n' ' ')"
    if [[ -n "${PROFILE_EMBEDDED_SHA1:-}" && -n "${KEYCHAIN_SHA1S// /}" ]]; then
      if ! echo " $KEYCHAIN_SHA1S " | grep -q " ${PROFILE_EMBEDDED_SHA1} "; then
        echo ""
        echo "ERROR: DEXT provisioning profile does not match your Keychain Apple Development certificate."
        echo "Fix: regenerate the DEXT profile selecting the Apple Development cert you have locally, then run:"
        echo "  ./scripts/ojd signing install-profiles"
        echo "  ./scripts/ojd signing configure"
        exit 1
      fi
    fi

    if [[ -n "${PROFILE_TEAM:-}" && -n "${CERT_OU:-}" && "$PROFILE_TEAM" != "$CERT_OU" ]]; then
      echo ""
      echo "ERROR: Signing team mismatch for DriverKit extension."
      echo "  DEXT profile team: $PROFILE_TEAM"
      echo "  Apple Dev cert OU: $CERT_OU"
      exit 1
    fi
  fi

  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
  local XCODE_CLANG XCODE_CLANGXX
  XCODE_CLANG="$(xcrun --find clang)"
  XCODE_CLANGXX="$(xcrun --find clang++ 2>/dev/null || true)"
  [[ -n "$XCODE_CLANGXX" ]] || XCODE_CLANGXX="$(dirname "$XCODE_CLANG")/clang++"
  export PATH="$(dirname "$XCODE_CLANG"):/usr/bin:/bin:/usr/sbin:/sbin"
  echo "  Compiler: $("$XCODE_CLANG" --version | head -n 1)"
  mkdir -p "$DEXT_BUILD_DIR/Index.noindex/DataStore"

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

  [[ -d "$DEXT_PRODUCT" ]] || die ".dext not found at expected path: $DEXT_PRODUCT"

  if [[ -n "$DEXT_BUNDLE_VERSION" ]]; then
    plutil -replace CFBundleVersion -string "$DEXT_BUNDLE_VERSION" "$DEXT_PRODUCT/Info.plist"
  fi

  echo "Built: $DEXT_PRODUCT"

  local GUI_APP="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
  local DEXT_SYSEXT="$GUI_APP/Contents/Library/SystemExtensions"
  local DEXT_BUNDLE_ID
  DEXT_BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$DEXT_PRODUCT/Info.plist")
  local DEXT_FILENAME="${DEXT_BUNDLE_ID}.dext"

  if [[ -d "$GUI_APP" ]]; then
    echo "Embedding dext into app bundle..."
    mkdir -p "$DEXT_SYSEXT"
    rm -rf "$DEXT_SYSEXT/$DEXT_FILENAME"
    rm -rf "$DEXT_SYSEXT/OpenJoystickVirtualHID.dext" 2>/dev/null || true
    cp -R "$DEXT_PRODUCT" "$DEXT_SYSEXT/$DEXT_FILENAME"

    local DEXT_EXEC_NAME
    DEXT_EXEC_NAME=$(ls "$DEXT_SYSEXT/$DEXT_FILENAME/" | grep -v -E 'Info\.plist|_CodeSignature|embedded\.provisionprofile' | head -1)
    chmod +x "$DEXT_SYSEXT/$DEXT_FILENAME/$DEXT_EXEC_NAME"
    plutil -replace CFBundleExecutable -string "$DEXT_EXEC_NAME" \
      "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist" 2>/dev/null \
      || plutil -insert CFBundleExecutable -string "$DEXT_EXEC_NAME" \
        "$DEXT_SYSEXT/$DEXT_FILENAME/Info.plist"

    local DEXT_ENTITLEMENTS_TMP="$PROJECT_DIR/.build/dext-entitlements.plist"
    codesign -d --entitlements - --xml "$DEXT_SYSEXT/$DEXT_FILENAME" > "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null \
      || die "Failed to extract entitlements from dext"

    if [[ "$OJD_ENV" == "release" ]]; then
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Delete :get-task-allow" "$DEXT_ENTITLEMENTS_TMP" 2>/dev/null || true
    fi

    local DEXT_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der --entitlements "$DEXT_ENTITLEMENTS_TMP")
    if [[ "$OJD_ENV" == "release" ]]; then
      DEXT_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${DEXT_SIGN_ARGS[@]}" "$DEXT_SYSEXT/$DEXT_FILENAME"

    [[ -f "$GUI_ENTITLEMENTS" ]] || resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
    local APP_SIGN_ARGS=(--sign "$CODESIGN_IDENTITY" --force --generate-entitlement-der --entitlements "$GUI_ENTITLEMENTS")
    if [[ "$OJD_ENV" == "release" ]]; then
      APP_SIGN_ARGS+=(--options runtime --timestamp)
    fi
    codesign "${APP_SIGN_ARGS[@]}" "$GUI_APP"

    if [[ "${OJD_SKIP_INSTALL:-0}" != "1" ]]; then
      echo "Installing to /Applications/OpenJoystickDriver.app..."
      rm -rf /Applications/OpenJoystickDriver.app
      cp -R "$GUI_APP" /Applications/
      echo "Copied to /Applications"
    else
      echo "Skipping /Applications install (OJD_SKIP_INSTALL=1)"
    fi
  else
    echo "ERROR: GUI app bundle not found at $GUI_APP"
    echo "Fix: run: ./scripts/ojd build dev"
    exit 1
  fi

  echo ""
  echo "DriverKit extension build complete."
  echo "  .dext: $DEXT_PRODUCT"
}

next_dext_bundle_version() {
  local max_version=0
  local candidate

  candidate=$(plutil -extract CFBundleVersion raw "$PROJECT_DIR/DriverKitExtension/Info.plist" 2>/dev/null || echo "")
  if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
    max_version="$candidate"
  fi

  candidate=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext/Info.plist \
    2>/dev/null || echo "")
  if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
    max_version="$candidate"
  fi

  while IFS= read -r candidate; do
    if [[ "$candidate" =~ ^[0-9]+$ && "$candidate" -gt "$max_version" ]]; then
      max_version="$candidate"
    fi
  done < <(
    systemextensionsctl list 2>/dev/null \
      | sed -n 's/.*com\.openjoystickdriver\.VirtualHIDDevice (1\.0\/\([0-9][0-9]*\)).*/\1/p'
  )

  echo $((max_version + 1))
}

rebuild_fast() {
  local APP_DST="/Applications/OpenJoystickDriver.app"
  local APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

  [[ -d "$APP_DST" ]] || die "$APP_DST not found. Run ./scripts/ojd rebuild dev once first."

  echo "=== Step 1: Build app (no dext) ==="
  build_app_bundle

  echo ""
  echo "=== Step 2: Preserve embedded system extension ==="
  local DEXT_DIR_DST="$APP_DST/Contents/Library/SystemExtensions"
  local DEXT_DIR_SRC="$APP_SRC/Contents/Library/SystemExtensions"
  if [[ -d "$DEXT_DIR_DST" ]]; then
    rm -rf "$DEXT_DIR_SRC" 2>/dev/null || true
    mkdir -p "$DEXT_DIR_SRC"
    cp -R "$DEXT_DIR_DST/"* "$DEXT_DIR_SRC/" 2>/dev/null || true
    echo "  Preserved: $DEXT_DIR_DST"
  else
    echo "  WARN: No SystemExtensions folder in $APP_DST (sysext may not be installed yet)"
  fi

  echo ""
  echo "=== Step 2.5: Re-sign app bundle (required) ==="
  [[ -f "$GUI_ENTITLEMENTS" ]] || resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
  _require_codesign_identity
  echo "  Signing: $APP_SRC"
  ojd_sign "$APP_SRC" --entitlements "$GUI_ENTITLEMENTS"
  echo "  Verifying signature (strict)..."
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_SRC" >/dev/null 2>&1 \
    || die "App signature verification failed after re-sign (run codesign --verify to see why)."
  echo "  ✓ Signature OK"

  echo ""
  echo "=== Step 3: Install app (without triggering sysext upgrade) ==="
  rm -rf "$APP_DST"
  cp -R "$APP_SRC" "$APP_DST"
  xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
  echo "  Copied to $APP_DST"

  echo ""
  echo "=== Step 4: Restart daemon ==="
  : > /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || true
  : > /tmp/com.openjoystickdriver.daemon.err 2>/dev/null || true
  local APP_BIN="$APP_DST/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless restart; then
    echo "  ✓ Daemon restarted"
  else
    echo "  ✗ Daemon restart failed"
    echo "    Fix: run: $APP_BIN --headless install"
  fi

  echo ""
  echo "=== Step 5: Launch app ==="
  open "$APP_DST" || true
  echo "  Launched OpenJoystickDriver"
}

rebuild_full() {
  echo "=== Step 1: Nuke all stale state ==="
  nuke_all

  echo ""
  echo "=== Step 2: Build app ==="
  build_app_bundle

  echo ""
  echo "=== Step 3: Build dext ==="
  local DEXT_VER
  DEXT_VER="$(next_dext_bundle_version)"
  echo "  Using CFBundleVersion=$DEXT_VER"
  DEXT_BUNDLE_VERSION="$DEXT_VER" build_dext_bundle

  echo ""
  echo "=== Step 4: Verify bundle IDs ==="
  local APP_ID DEXT_ID
  APP_ID=$(plutil -extract CFBundleIdentifier raw .build/debug/OpenJoystickDriver.app/Contents/Info.plist 2>/dev/null || echo "MISSING")
  DEXT_ID=$(plutil -extract CFBundleIdentifier raw ".build/debug/OpenJoystickDriver.app/Contents/Library/SystemExtensions/${APP_ID}.VirtualHIDDevice.dext/Info.plist" 2>/dev/null || echo "MISSING")
  echo "  App:  $APP_ID"
  echo "  Dext: $DEXT_ID"
  [[ "$DEXT_ID" == "$APP_ID"* ]] || die "PREFIX MISMATCH — dext will not be found in app bundle"

  if [[ "$OJD_ENV" == "release" ]]; then
    echo ""
    echo "=== Notarizing ==="
    /usr/bin/env bash "$SCRIPT_DIR/ojd-notarize.sh" submit
  fi

  echo ""
  echo "=== Step 5: Submit sysext activation ==="
  : > /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || true
  : > /tmp/com.openjoystickdriver.daemon.err 2>/dev/null || true
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless sysext install; then
    echo "  ✓ Sysext activation request submitted"
  else
    echo "  ✗ Sysext activation request failed"
    echo "    Fix: run: $APP_BIN --headless sysext install"
  fi

  echo ""
  echo "=== Step 6: Wait for sysext activation ==="
  echo ""

  local NEW_VERSION
  NEW_VERSION=$(plutil -extract CFBundleVersion raw \
    /Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/com.openjoystickdriver.VirtualHIDDevice.dext/Info.plist 2>/dev/null || echo "")
  local SYSEXT_TIMEOUT=30 SYSEXT_ELAPSED=0
  while (( SYSEXT_ELAPSED < SYSEXT_TIMEOUT )); do
    sleep 2
    SYSEXT_ELAPSED=$(( SYSEXT_ELAPSED + 2 ))
    if systemextensionsctl list 2>&1 | grep -q "1.0/${NEW_VERSION}.*activated enabled"; then
      echo "  ✓ Sysext v${NEW_VERSION} activated after ${SYSEXT_ELAPSED}s"
      break
    fi
    printf "  …waiting for sysext v%s (%ds)\n" "$NEW_VERSION" "$SYSEXT_ELAPSED"
  done
  if (( SYSEXT_ELAPSED >= SYSEXT_TIMEOUT )); then
    echo "  ⚠ Sysext v${NEW_VERSION} not activated after ${SYSEXT_TIMEOUT}s — continuing anyway"
  fi

  echo ""
  echo "=== Step 7: Wait for dext start ==="
  local TIMEOUT=60 ELAPSED=0
  while (( ELAPSED < TIMEOUT )); do
    sleep 3
    ELAPSED=$(( ELAPSED + 3 ))
    if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null | grep -q "start fail"; then
      echo "  ✗ Kernel DK log shows 'start fail' after ${ELAPSED}s"
      break
    fi
    if $LOG show --last 10s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null | grep -q "user server timeout"; then
      echo "  ✗ Kernel DK log shows 'user server timeout' after ${ELAPSED}s"
      break
    fi
    if $LOG show --last 10s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID:"' --info --debug --style compact 2>/dev/null | grep -q "OpenJoystickVirtualHID:"; then
      echo "  ✓ Dext logs detected after ${ELAPSED}s"
      break
    fi
    printf "  …%ds\n" "$ELAPSED"
  done
  if (( ELAPSED >= TIMEOUT )); then
    echo "  ⚠ Timed out after ${TIMEOUT}s — no dext logs or start fail detected"
  fi

  echo ""
  echo "=== Step 8: Restart daemon ==="
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  if "$APP_BIN" --headless restart; then
    echo "  ✓ Daemon restarted"
  else
    echo "  ✗ Daemon restart failed"
    echo "    Fix: run: $APP_BIN --headless install"
  fi

  echo ""
  echo "=== Step 9: Diagnostics ==="
  echo "--- Dext os_log (last 60s) ---"
  $LOG show --last 60s --predicate 'eventMessage CONTAINS "OpenJoystickVirtualHID"' --info --debug --style compact 2>/dev/null || echo "(none)"
  echo ""
  echo "--- Kernel DK logs (last 60s) ---"
  $LOG show --last 60s --predicate 'process == "kernel" AND eventMessage CONTAINS "DK:"' --info --debug --style compact 2>/dev/null || echo "(none)"
  echo ""
  echo "--- Sysext status ---"
  systemextensionsctl list 2>&1 || true
  echo ""
  echo "--- Daemon log (fresh) ---"
  tail -10 /tmp/com.openjoystickdriver.daemon.out 2>/dev/null || echo "(no daemon log)"
}

run_lint() {
  command -v swiftlint >/dev/null 2>&1 || die "swiftlint not found (brew install swiftlint)"
  cd "$PROJECT_DIR"
  swiftlint lint --strict
}

cmd="${1:-}"
sub="${2:-}"

case "$cmd" in
  ""|-h|--help|help)
    usage
    exit 0
    ;;
  nuke)
    nuke_all
    ;;
  lint)
    run_lint
    ;;
  build)
    case "$sub" in
      dev|release)
        build_app_bundle
        ;;
      dext)
        build_dext_bundle
        ;;
      *)
        die "Unknown: build $sub (expected: dev | release | dext)"
        ;;
    esac
    ;;
  rebuild)
    case "$sub" in
      dev|release)
        rebuild_full
        ;;
      *)
        die "Unknown: rebuild $sub (expected: dev | release)"
        ;;
    esac
    ;;
  rebuild-fast)
    case "$sub" in
      dev)
        rebuild_fast
        ;;
      *)
        die "Unknown: rebuild-fast $sub (expected: dev)"
        ;;
    esac
    ;;
  *)
    die "Unknown command: $cmd"
    ;;
esac
