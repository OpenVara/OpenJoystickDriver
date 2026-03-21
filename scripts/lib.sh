#!/usr/bin/env bash
# Shared constants and helpers for OpenJoystickDriver build scripts.
# Source this file: source "$(dirname "$0")/lib.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment: scripts/.env.dev or scripts/.env.release
# Override with OJD_ENV=release or OJD_ENV=dev (default: dev)
OJD_ENV="${OJD_ENV:-dev}"
_ENV_FILE="$SCRIPT_DIR/.env.$OJD_ENV"
if [[ -f "$_ENV_FILE" ]]; then
  set -a
  source "$_ENV_FILE"
  set +a
fi
unset _ENV_FILE

# Workaround: xcrun --sdk hangs on macOS 26.3.1 (Xcode 26.3).
# Export SDKROOT so swift build, xcodebuild, and clang skip the xcrun lookup.
export SDKROOT="${SDKROOT:-$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"

IDENTITY="${CODESIGN_IDENTITY:--}"
DAEMON_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriverDaemon"
GUI_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriver"
DAEMON_RELEASE="$PROJECT_DIR/.build/apple/Products/Release/OpenJoystickDriverDaemon"
GUI_RELEASE="$PROJECT_DIR/.build/apple/Products/Release/OpenJoystickDriver"

# Active binary paths (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  DAEMON_BIN="$DAEMON_RELEASE"
  GUI_BIN="$GUI_RELEASE"
else
  DAEMON_BIN="$DAEMON_DEBUG"
  GUI_BIN="$GUI_DEBUG"
fi

# Template paths (source-controlled, contain ${DEVELOPMENT_TEAM} placeholder)
GUI_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements.template"
DAEMON_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements.template"

# Resolved paths (generated at build time into .build/)
GUI_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriver.entitlements"
DAEMON_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriverDaemon.entitlements"

# ---------------------------------------------------------------------------
# Universal (fat) static libusb
# Homebrew only ships arm64 on Apple Silicon. For release builds we
# cross-compile x86_64 from source and lipo both slices into one .a
# so swift build links statically instead of against Homebrew's dylib.
# ---------------------------------------------------------------------------
LIBUSB_VERSION="1.0.29"
LIBUSB_CACHE_DIR="$PROJECT_DIR/.build/libusb-universal"
LIBUSB_UNIVERSAL_A="$LIBUSB_CACHE_DIR/lib/libusb-1.0.a"
LIBUSB_PC="$LIBUSB_CACHE_DIR/libusb-1.0.pc"

build_universal_libusb() {
  local SDK_PATH="$SDKROOT"
  echo "Building universal libusb ${LIBUSB_VERSION} (arm64 + x86_64)..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tarball="$tmpdir/libusb.tar.bz2"
  echo "  Downloading libusb ${LIBUSB_VERSION}..."
  curl -fsSL \
    "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2" \
    -o "$tarball"

  local ncpu
  ncpu="$(sysctl -n hw.ncpu)"

  echo "  Configuring arm64..."
  mkdir -p "$tmpdir/src-arm64"
  tar -xjf "$tarball" -C "$tmpdir/src-arm64" --strip-components=1
  (
    cd "$tmpdir/src-arm64"
    ./configure \
      CC="clang" \
      CFLAGS="-arch arm64 -target arm64-apple-macos13.0 -isysroot $SDK_PATH" \
      LDFLAGS="-arch arm64 -target arm64-apple-macos13.0" \
      --host=aarch64-apple-darwin \
      --prefix="$tmpdir/install-arm64" \
      --disable-shared --enable-static \
      --quiet 2>&1 | tail -5
    make -j"$ncpu" install --quiet
  )

  echo "  Configuring x86_64..."
  mkdir -p "$tmpdir/src-x86_64"
  tar -xjf "$tarball" -C "$tmpdir/src-x86_64" --strip-components=1
  (
    cd "$tmpdir/src-x86_64"
    ./configure \
      CC="clang" \
      CFLAGS="-arch x86_64 -target x86_64-apple-macos13.0 -isysroot $SDK_PATH" \
      LDFLAGS="-arch x86_64 -target x86_64-apple-macos13.0" \
      --host=x86_64-apple-darwin \
      --prefix="$tmpdir/install-x86_64" \
      --disable-shared --enable-static \
      --quiet 2>&1 | tail -5
    make -j"$ncpu" install --quiet
  )

  mkdir -p "$LIBUSB_CACHE_DIR/lib" "$LIBUSB_CACHE_DIR/include"
  lipo -create \
    "$tmpdir/install-arm64/lib/libusb-1.0.a" \
    "$tmpdir/install-x86_64/lib/libusb-1.0.a" \
    -output "$LIBUSB_UNIVERSAL_A"
  cp -r "$tmpdir/install-arm64/include/libusb-1.0" "$LIBUSB_CACHE_DIR/include/"

  echo "  Universal libusb ready: $(lipo -info "$LIBUSB_UNIVERSAL_A")"
}

setup_libusb_pkgconfig() {
  if [[ ! -f "$LIBUSB_UNIVERSAL_A" ]]; then
    build_universal_libusb
  else
    echo "Universal libusb cache hit: $LIBUSB_UNIVERSAL_A"
  fi

  cat > "$LIBUSB_PC" << EOF
prefix=$LIBUSB_CACHE_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libusb-1.0
Description: C API for USB device access (universal binary)
Version: $LIBUSB_VERSION
Libs: -L\${libdir} -lusb-1.0
Cflags: -I\${includedir}/libusb-1.0
EOF

  export PKG_CONFIG_PATH="$LIBUSB_CACHE_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
}

# Provisioning profiles (selected by OJD_ENV)
if [[ "$OJD_ENV" == "release" ]]; then
  DAEMON_PROFILE="${DAEMON_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile}"
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
else
  DAEMON_PROFILE="${DAEMON_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile}"
  GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"
fi

# Verify that the provisioning profile's signing certificate matches the
# keychain identity. Fails with a clear message instead of letting AMFI
# reject the app at launch with error 163.
# Usage: verify_profile_cert <profile_path> <signing_identity>
verify_profile_cert() {
  local profile="$1" identity="$2"
  local profile_sha1 keychain_sha1
  local tmpder
  tmpder="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmpder'" RETURN

  # Extract first DeveloperCertificate from profile to a temp file
  # (binary DER data contains null bytes — can't store in bash variables)
  security cms -D -i "$profile" 2>/dev/null \
    | plutil -extract DeveloperCertificates.0 raw -o - - \
    | base64 -d > "$tmpder" 2>/dev/null

  profile_sha1=$(openssl x509 -inform DER -in "$tmpder" -noout -fingerprint -sha1 2>/dev/null \
    | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')

  keychain_sha1=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "$identity" | head -1 \
    | awk '{print $2}' | tr '[:upper:]' '[:lower:]')

  if [[ -z "$profile_sha1" || -z "$keychain_sha1" ]]; then
    echo "WARNING: Could not extract SHA1 for profile cert verification (profile_sha1=${profile_sha1:-empty}, keychain_sha1=${keychain_sha1:-empty})"
    return 0  # can't verify, don't block
  fi

  if [[ "$profile_sha1" != "$keychain_sha1" ]]; then
    local profile_serial keychain_serial
    profile_serial=$(openssl x509 -inform DER -in "$tmpder" -noout -serial 2>/dev/null \
      | sed 's/serial=//')

    # Export keychain cert as PEM to extract its serial
    keychain_serial=$(security find-certificate -c "$identity" -p 2>/dev/null \
      | openssl x509 -noout -serial 2>/dev/null \
      | sed 's/serial=//')

    echo ""
    echo "ERROR: Provisioning profile cert does not match signing identity!"
    echo ""
    "$SCRIPT_DIR/check-profiles.sh"
    echo ""
    return 1
  fi
}

# Sign binary with configured identity.
# Usage: ojd_sign <binary> [--entitlements <path>]
# NOTE: --entitlements must be the first extra arg pair (before any other flags).
# When OJD_ENV=release, adds hardened runtime (required for notarization).
ojd_sign() {
  local binary="$1"
  local extra_args=()
  if [[ "${2:-}" == "--entitlements" && -n "${3:-}" ]]; then
    extra_args=(--entitlements "$3")
  fi
  if [[ "$OJD_ENV" == "release" ]]; then
    extra_args+=(--options runtime --timestamp)
  fi
  codesign --sign "$IDENTITY" --force --generate-entitlement-der "${extra_args[@]}" "$binary"
}

# Resolve entitlements templates: replace ${DEVELOPMENT_TEAM} with actual value.
# Usage: resolve_entitlements <template> <output>
resolve_entitlements() {
  local template="$1" output="$2"
  sed "s/\${DEVELOPMENT_TEAM}/$DEVELOPMENT_TEAM/g" "$template" > "$output"
}
