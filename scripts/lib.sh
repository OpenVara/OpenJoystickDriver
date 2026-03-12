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
IDENTITY="${CODESIGN_IDENTITY:--}"
DAEMON_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriverDaemon"
GUI_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriver"

# Template paths (source-controlled, contain ${DEVELOPMENT_TEAM} placeholder)
GUI_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements.template"
DAEMON_ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements.template"

# Resolved paths (generated at build time into .build/)
GUI_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriver.entitlements"
DAEMON_ENTITLEMENTS="$PROJECT_DIR/.build/OpenJoystickDriverDaemon.entitlements"

# Provisioning profiles (development)
DAEMON_PROFILE="${DAEMON_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile}"
GUI_PROFILE="${GUI_PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"

# Sign binary with configured identity.
# Usage: ojd_sign <binary> [--entitlements <path>]
# When OJD_ENV=release, adds hardened runtime (required for notarization).
ojd_sign() {
  local binary="$1"
  local extra_args=()
  if [[ "${2:-}" == "--entitlements" && -n "${3:-}" ]]; then
    extra_args=(--entitlements "$3")
  fi
  if [[ "$OJD_ENV" == "release" ]]; then
    extra_args+=(--options runtime)
  fi
  codesign --sign "$IDENTITY" --force --generate-entitlement-der "${extra_args[@]}" "$binary"
}

# Resolve entitlements templates: replace ${DEVELOPMENT_TEAM} with actual value.
# Usage: resolve_entitlements <template> <output>
resolve_entitlements() {
  local template="$1" output="$2"
  sed "s/\${DEVELOPMENT_TEAM}/$DEVELOPMENT_TEAM/g" "$template" > "$output"
}
