#!/usr/bin/env bash
# Shared constants and helpers for OpenJoystickDriver build scripts.
# Source this file: source "$(dirname "$0")/lib.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENTITLEMENTS="$PROJECT_DIR/Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"
IDENTITY="${CODESIGN_IDENTITY:--}"
DAEMON_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriverDaemon"
GUI_DEBUG="$PROJECT_DIR/.build/debug/OpenJoystickDriver"

# Sign binary with configured identity.
# Usage: ojd_sign <binary> [--entitlements <path>]
ojd_sign() {
  local binary="$1"
  local extra_args=()
  if [[ "${2:-}" == "--entitlements" && -n "${3:-}" ]]; then
    extra_args=(--entitlements "$3")
  fi
  codesign --sign "$IDENTITY" --force "${extra_args[@]}" "$binary"
}
