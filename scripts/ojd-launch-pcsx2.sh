#!/usr/bin/env bash
# Launch PCSX2 with OpenJoystickDriver's SDL mapping override.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCSX2_APP="${PCSX2_APP:-/Applications/PCSX2.app}"
PCSX2_BIN="$PCSX2_APP/Contents/MacOS/PCSX2"
OJD_DB="$ROOT/Resources/SDL/openjoystickdriver.gamecontrollerdb.txt"
OJD_CLI="${OJD_CLI:-/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver}"

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

if [[ "${OJD_SKIP_PCSX2_ROUTING:-0}" != "1" && -x "$OJD_CLI" ]]; then
"$OJD_CLI" --headless compat sdl-macos >/dev/null || {
    echo "WARN: could not set OpenJoystickDriver compatibility identity to generic" >&2
  }
  "$OJD_CLI" --headless output secondary >/dev/null || {
    echo "WARN: could not set OpenJoystickDriver output mode to secondary" >&2
  }
fi

exec "$PCSX2_BIN" "$@"
