#!/usr/bin/env bash
# Publisher release script — builds signed universal binary and notarizes it.
#
# REQUIREMENTS (publisher only — contributors use scripts/sign-dev.sh instead):
#   1. Valid Apple Developer account with Developer ID Application certificate.
#   2. Copy .env.example to .env and fill in all four values.
#   3. Developer ID Application certificate must be installed in your Keychain.
#
# USAGE:
#   ./scripts/build-release.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_ENTITLEMENTS="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"

ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env not found."
  echo "Copy .env.example to .env and fill in your Apple Developer credentials."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY not set in .env}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID not set in .env}"
: "${APPLE_ID:?APPLE_ID not set in .env}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD not set in .env}"

# ---------------------------------------------------------------------------
# Universal (fat) libusb — Homebrew only ships arm64 on Apple Silicon.
# We cross-compile x86_64 from source and lipo both slices into one .a that
# SPM/xcodebuild can link when targeting both architectures.
# Result is cached under .build/libusb-universal so it only builds once.
# ---------------------------------------------------------------------------
LIBUSB_VERSION="1.0.29"
LIBUSB_CACHE_DIR="$PROJECT_DIR/.build/libusb-universal"
LIBUSB_UNIVERSAL_A="$LIBUSB_CACHE_DIR/lib/libusb-1.0.a"
LIBUSB_PC="$LIBUSB_CACHE_DIR/libusb-1.0.pc"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

build_universal_libusb() {
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

  # Write pkg-config .pc that points to our fat static lib.
  # When SPM resolves CLibUSB via pkgConfig, it will pick up -L and -I from
  # this file and linker will find both arm64 and x86_64 slices.
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

echo "Running lint checks..."
cd "$PROJECT_DIR"
swiftlint lint --strict

setup_libusb_pkgconfig

echo "Building universal binaries..."
swift build -c release \
  --product OpenJoystickDriverDaemon \
  --product OpenJoystickDriver \
  --arch arm64 \
  --arch x86_64

RELEASE="$PROJECT_DIR/.build/apple/Products/Release"
DAEMON="$RELEASE/OpenJoystickDriverDaemon"
GUI="$RELEASE/OpenJoystickDriver"

echo "Signing daemon (USB entitlements + hardened runtime)..."
codesign \
  --sign "$CODESIGN_IDENTITY" \
  --force \
  --options runtime \
  --entitlements "$DAEMON_ENTITLEMENTS" \
  "$DAEMON"

echo "Signing GUI (hardened runtime)..."
codesign \
  --sign "$CODESIGN_IDENTITY" \
  --force \
  --options runtime \
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
echo "  • Package into a .dmg / Homebrew formula for distribution."
