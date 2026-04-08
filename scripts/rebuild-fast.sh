#!/usr/bin/env bash
# Fast rebuild during iteration (no sysext upgrade):
# - builds + signs GUI + daemon
# - preserves the existing embedded system extension in /Applications
# - restarts the daemon
#
# Use this while streaming / when you cannot reboot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

APP_DST="/Applications/OpenJoystickDriver.app"
APP_SRC="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"

if [[ ! -d "$APP_DST" ]]; then
  echo "ERROR: $APP_DST not found."
  echo "Fix: run ./scripts/rebuild.sh once to install the system extension."
  exit 1
fi

echo "=== Step 1: Build app (no dext) ==="
"$SCRIPT_DIR/build-dev.sh"

echo ""
echo "=== Step 2: Preserve embedded system extension ==="
DEXT_DIR_DST="$APP_DST/Contents/Library/SystemExtensions"
DEXT_DIR_SRC="$APP_SRC/Contents/Library/SystemExtensions"

if [[ -d "$DEXT_DIR_DST" ]]; then
  mkdir -p "$DEXT_DIR_SRC"
  rm -rf "$DEXT_DIR_SRC"
  mkdir -p "$DEXT_DIR_SRC"
  cp -R "$DEXT_DIR_DST/"* "$DEXT_DIR_SRC/" 2>/dev/null || true
  echo "  Preserved: $DEXT_DIR_DST"
else
  echo "  WARN: No SystemExtensions folder in $APP_DST (sysext may not be installed yet)"
fi

echo ""
echo "=== Step 2.5: Re-sign app bundle (required) ==="
#
# Preserving the existing .dext modifies the app bundle AFTER it was signed by build-dev.sh.
# If we don't re-sign here, macOS will reject the app as "tampered with", and:
#   - `codesign --verify --deep --strict` fails with "a sealed resource is missing or invalid"
#   - SMAppService daemon install fails (and XPC will never connect reliably)
#
# IMPORTANT: We re-sign the *source* app in .build first, then copy to /Applications.
if [[ ! -f "$GUI_ENTITLEMENTS" ]]; then
  mkdir -p "$PROJECT_DIR/.build"
  resolve_entitlements "$GUI_ENTITLEMENTS_TEMPLATE" "$GUI_ENTITLEMENTS"
fi

if [[ "${IDENTITY:--}" == "-" ]]; then
  echo "ERROR: CODESIGN_IDENTITY not set. macOS 26+ requires Apple Development signing."
  echo "Fix: run ./scripts/configure-signing.sh"
  exit 1
fi

echo "  Signing: $APP_SRC"
ojd_sign "$APP_SRC" --entitlements "$GUI_ENTITLEMENTS"

echo "  Verifying signature (strict)..."
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_SRC" >/dev/null 2>&1; then
  echo "ERROR: App signature verification failed after re-sign."
  echo "Run this to see the exact reason:"
  echo "  /usr/bin/codesign --verify --deep --strict --verbose=2 \"$APP_SRC\""
  exit 1
fi
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
APP_BIN="$APP_DST/Contents/MacOS/OpenJoystickDriver"
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

echo ""
echo "Tip: If DriverKit output is unstable (sysext upgrade / OSSystemExtension error 4),"
echo "     open the menubar app and switch Mode → Compatibility."
