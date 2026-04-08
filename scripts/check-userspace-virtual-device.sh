#!/usr/bin/env bash
# Checks whether the daemon is allowed to create an IOHIDUserDevice.
# Prints only booleans / PASS/FAIL (no sensitive identifiers).
set -euo pipefail

ENTITLEMENT_KEY="com.apple.developer.hid.virtual.device"

PROFILE_DEV_DEFAULT="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile"
PROFILE_REL_DEFAULT="$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile"
DAEMON_BIN_DEFAULT="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"

PROFILE_DEV="${1:-$PROFILE_DEV_DEFAULT}"
PROFILE_REL="${2:-$PROFILE_REL_DEFAULT}"
DAEMON_BIN="${3:-$DAEMON_BIN_DEFAULT}"

usage() {
  cat <<'TXT'
Usage:
  ./scripts/check-userspace-virtual-device.sh [DEV_PROFILE] [RELEASE_PROFILE] [DAEMON_BIN]

Defaults:
  DEV_PROFILE     ~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile
  RELEASE_PROFILE ~/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile
  DAEMON_BIN      /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon
TXT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

decode_profile() {
  local profile="$1"
  if security cms -D -i "$profile" 2>/dev/null; then
    return 0
  fi
  openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null
}

check_profile() {
  local label="$1" profile="$2"
  if [[ ! -f "$profile" ]]; then
    echo "[WARN] ${label} profile not found"
    return 0
  fi

  local ok="false"
  if decode_profile "$profile" 2>/dev/null | plutil -p - 2>/dev/null | rg -q "\"${ENTITLEMENT_KEY}\""; then
    ok="true"
  fi

  if [[ "$ok" == "true" ]]; then
    echo "[PASS] ${label} profile has ${ENTITLEMENT_KEY}"
  else
    echo "[FAIL] ${label} profile missing ${ENTITLEMENT_KEY}"
  fi
}

check_codesign_entitlements() {
  local bin="$1"
  if [[ ! -f "$bin" ]]; then
    echo "[WARN] Daemon binary not found at expected path"
    return 0
  fi

  # NOTE: `codesign -d --entitlements :-` is deprecated on newer macOS and may print warnings.
  # Use the human-readable dump output and match on the entitlement key.
  local dump
  dump="$(codesign -d --entitlements - "$bin" 2>/dev/null || true)"
  if [[ -z "$dump" ]]; then
    echo "[FAIL] Could not read daemon binary entitlements (codesign returned no output)"
    return 0
  fi

  if echo "$dump" | rg -q "\\[Key\\] ${ENTITLEMENT_KEY}"; then
    echo "[PASS] Daemon binary entitlement present (${ENTITLEMENT_KEY})"
  else
    echo "[FAIL] Daemon binary entitlement missing (${ENTITLEMENT_KEY})"
    echo "       Fix: enable this entitlement on Identifier com.openjoystickdriver.daemon"
    echo "            then regenerate/reinstall daemon profiles and rebuild."
  fi
}

echo "=== User-Space Virtual Device Check ==="
check_profile "Daemon dev" "$PROFILE_DEV"
check_profile "Daemon release" "$PROFILE_REL"
check_codesign_entitlements "$DAEMON_BIN"
