#!/usr/bin/env bash
# Launch an SDL app through OJD's GameController rumble route.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OJD_CLI="${OJD_CLI:-/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd launch sdl-gamecontroller <app-path> [-- app args...]

Examples:
  ./scripts/ojd launch sdl-gamecontroller /Applications/PCSX2.app
  ./scripts/ojd launch sdl-gamecontroller /Applications/DuckStation.app -- -fullscreen

This experimental route selects OJD's apple-gamecontroller compatibility
identity and launches the SDL app with SDL's GameController/MFI backend enabled.
Use `./scripts/ojd diagnose sdl3-gamecontroller` to verify whether the target
SDL build enumerates the virtual GCController.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

APP_PATH="$1"
shift
if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ ! -e "$APP_PATH" ]]; then
  die "app path not found: $APP_PATH"
fi

if [[ -x "$OJD_CLI" ]]; then
  "$OJD_CLI" --headless compat apple-gamecontroller >/dev/null || {
    echo "WARN: could not set OJD compatibility identity to apple-gamecontroller" >&2
  }
  "$OJD_CLI" --headless userspace on >/dev/null || {
    echo "WARN: could not enable OJD user-space output" >&2
  }
else
  echo "WARN: OJD CLI not found at $OJD_CLI; launching with SDL env only" >&2
fi

export SDL_JOYSTICK_MFI=1
export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
export SDL_JOYSTICK_IOKIT=0
export SDL_JOYSTICK_HIDAPI=0
export SDL_JOYSTICK_HIDAPI_XBOX=0
export SDL_JOYSTICK_HIDAPI_XBOX_360=0
export SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS=0
export SDL_JOYSTICK_HIDAPI_XBOX_ONE=0
export SDL_JOYSTICK_HIDAPI_GIP=0

launchctl setenv SDL_JOYSTICK_MFI "$SDL_JOYSTICK_MFI"
launchctl setenv SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS "$SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"
launchctl setenv SDL_JOYSTICK_IOKIT "$SDL_JOYSTICK_IOKIT"
launchctl setenv SDL_JOYSTICK_HIDAPI "$SDL_JOYSTICK_HIDAPI"
launchctl setenv SDL_JOYSTICK_HIDAPI_XBOX "$SDL_JOYSTICK_HIDAPI_XBOX"
launchctl setenv SDL_JOYSTICK_HIDAPI_XBOX_360 "$SDL_JOYSTICK_HIDAPI_XBOX_360"
launchctl setenv SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS "$SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS"
launchctl setenv SDL_JOYSTICK_HIDAPI_XBOX_ONE "$SDL_JOYSTICK_HIDAPI_XBOX_ONE"
launchctl setenv SDL_JOYSTICK_HIDAPI_GIP "$SDL_JOYSTICK_HIDAPI_GIP"

if [[ "$APP_PATH" == *.app ]]; then
  exec open "$APP_PATH" --args "$@"
fi

exec "$APP_PATH" "$@"
