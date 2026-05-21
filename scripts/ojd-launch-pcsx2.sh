#!/usr/bin/env bash
# Launch PCSX2 with OpenJoystickDriver's SDL mapping override.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCSX2_APP="${PCSX2_APP:-/Applications/PCSX2.app}"
PCSX2_BIN="$PCSX2_APP/Contents/MacOS/PCSX2"
OJD_DB="$ROOT/Resources/SDL/openjoystickdriver.gamecontrollerdb.txt"
OJD_CLI="${OJD_CLI:-/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver}"
RUMBLE_ROUTE="${OJD_PCSX2_RUMBLE_ROUTE:-sdl}"

if [[ "${1:-}" == "--hidapi-rumble" ]]; then
  RUMBLE_ROUTE="hidapi"
  shift
elif [[ "${1:-}" == "--gamecontroller-rumble" ]]; then
  RUMBLE_ROUTE="gamecontroller"
  shift
elif [[ "${1:-}" == "--sdl" ]]; then
  RUMBLE_ROUTE="sdl"
  shift
fi

run_ojd_cli() {
  local limit="${OJD_PCSX2_ROUTE_TIMEOUT:-8}"
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= limit )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

set_launchenv() {
  local key="$1"
  local value="${2-}"
  if [[ -n "$value" ]]; then
    launchctl setenv "$key" "$value"
  else
    launchctl unsetenv "$key"
  fi
}

if [[ ! -x "$PCSX2_BIN" ]]; then
  echo "ERROR: PCSX2 binary not found: $PCSX2_BIN" >&2
  exit 2
fi

if [[ ! -f "$OJD_DB" ]]; then
  echo "ERROR: OpenJoystickDriver SDL mapping not found: $OJD_DB" >&2
  exit 2
fi

mapping="$(grep -v '^#' "$OJD_DB" | grep -v '^[[:space:]]*$' | paste -sd $'\n' -)"
if [[ -z "$mapping" ]]; then
  echo "ERROR: OpenJoystickDriver SDL mapping file is empty: $OJD_DB" >&2
  exit 2
fi

export SDL_GAMECONTROLLERCONFIG="$mapping"
export SDL_GAMECONTROLLERCONFIG_FILE="$OJD_DB"
if [[ "$RUMBLE_ROUTE" == "hidapi" ]]; then
  export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1
  export SDL_JOYSTICK_MFI=0
  export SDL_JOYSTICK_HIDAPI=1
  export SDL_JOYSTICK_IOKIT=0
elif [[ "$RUMBLE_ROUTE" == "gamecontroller" ]]; then
  export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD="${SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD:-}"
  export SDL_JOYSTICK_MFI=1
  export SDL_JOYSTICK_HIDAPI=0
  export SDL_JOYSTICK_IOKIT=0
else
  export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD="${SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD:-}"
  export SDL_JOYSTICK_MFI="${SDL_JOYSTICK_MFI:-}"
  export SDL_JOYSTICK_HIDAPI="${SDL_JOYSTICK_HIDAPI:-}"
  export SDL_JOYSTICK_IOKIT="${SDL_JOYSTICK_IOKIT:-}"
fi

export SDL_JOYSTICK_HIDAPI_XBOX=0
export SDL_JOYSTICK_HIDAPI_XBOX_360=0
export SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS=0
export SDL_JOYSTICK_HIDAPI_XBOX_ONE=0
export SDL_JOYSTICK_HIDAPI_GIP=0

if [[ "${OJD_SKIP_PCSX2_ROUTING:-0}" != "1" && -x "$OJD_CLI" ]]; then
  if [[ "$RUMBLE_ROUTE" == "hidapi" ]]; then
    run_ojd_cli "$OJD_CLI" --headless compat x360-hid >/dev/null || {
      echo "WARN: could not set OpenJoystickDriver compatibility identity to x360-hid" >&2
    }
    run_ojd_cli "$OJD_CLI" --headless userspace on >/dev/null || {
      echo "WARN: could not enable OpenJoystickDriver user-space output" >&2
    }
  elif [[ "$RUMBLE_ROUTE" == "gamecontroller" ]]; then
    run_ojd_cli "$OJD_CLI" --headless compat apple-gamecontroller >/dev/null || {
      echo "WARN: could not set OpenJoystickDriver compatibility identity to apple-gamecontroller" >&2
    }
    run_ojd_cli "$OJD_CLI" --headless userspace on >/dev/null || {
      echo "WARN: could not enable OpenJoystickDriver user-space output" >&2
    }
  else
    run_ojd_cli "$OJD_CLI" --headless compat sdl2-3 >/dev/null || {
      echo "WARN: could not set OpenJoystickDriver compatibility identity to sdl2-3" >&2
    }
    run_ojd_cli "$OJD_CLI" --headless output secondary >/dev/null || {
      echo "WARN: could not set OpenJoystickDriver output mode to secondary" >&2
    }
  fi
fi

# Launch the app bundle through LaunchServices so PCSX2 keeps its normal app
# identity, resource lookup, and Input Monitoring behavior. Directly exec'ing
# Contents/MacOS/PCSX2 can leave PCSX2 without the devices the .app can access.
set_launchenv SDL_GAMECONTROLLERCONFIG "$SDL_GAMECONTROLLERCONFIG"
set_launchenv SDL_GAMECONTROLLERCONFIG_FILE "$SDL_GAMECONTROLLERCONFIG_FILE"
if [[ "$RUMBLE_ROUTE" == "hidapi" ]]; then
  export SDL_JOYSTICK_HIDAPI_XBOX=1
  export SDL_JOYSTICK_HIDAPI_XBOX_360=1
fi
set_launchenv SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD "$SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD"
set_launchenv SDL_JOYSTICK_MFI "$SDL_JOYSTICK_MFI"
set_launchenv SDL_JOYSTICK_HIDAPI "$SDL_JOYSTICK_HIDAPI"
set_launchenv SDL_JOYSTICK_IOKIT "$SDL_JOYSTICK_IOKIT"
set_launchenv SDL_JOYSTICK_HIDAPI_XBOX "$SDL_JOYSTICK_HIDAPI_XBOX"
set_launchenv SDL_JOYSTICK_HIDAPI_XBOX_360 "$SDL_JOYSTICK_HIDAPI_XBOX_360"
set_launchenv SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS "$SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS"
set_launchenv SDL_JOYSTICK_HIDAPI_XBOX_ONE "$SDL_JOYSTICK_HIDAPI_XBOX_ONE"
set_launchenv SDL_JOYSTICK_HIDAPI_GIP "$SDL_JOYSTICK_HIDAPI_GIP"

exec open "$PCSX2_APP" --args "$@"
