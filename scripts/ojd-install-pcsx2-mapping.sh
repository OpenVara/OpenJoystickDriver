#!/usr/bin/env bash
# Install OpenJoystickDriver's SDL mapping into PCSX2's bundled controller DB.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCSX2_DB="${PCSX2_DB:-/Applications/PCSX2.app/Contents/Resources/game_controller_db.txt}"
OJD_DB="$ROOT/Resources/SDL/openjoystickdriver.gamecontrollerdb.txt"
GUID="0300f88c4a4f00004844000008040000"
OLD_GUID="0300f88c4a4f00004744000008040000"

if [[ ! -f "$PCSX2_DB" ]]; then
  echo "ERROR: PCSX2 controller DB not found: $PCSX2_DB" >&2
  exit 2
fi

if [[ ! -f "$OJD_DB" ]]; then
  echo "ERROR: OpenJoystickDriver SDL mapping not found: $OJD_DB" >&2
  exit 2
fi

backup="${PCSX2_DB}.ojd-backup-$(date +%Y%m%d%H%M%S)"
if ! cp "$PCSX2_DB" "$backup" 2>/dev/null; then
  cat >&2 <<TXT
ERROR: Cannot write to PCSX2's bundled controller database:
  $PCSX2_DB

Use the non-invasive launcher instead:
  ./scripts/ojd launch pcsx2

That launch path sets SDL_GAMECONTROLLERCONFIG_FILE and also switches
OpenJoystickDriver to the validated PCSX2 route:
compat sdl-macos
  output secondary

To make normal PCSX2 launches use this mapping, re-run this installer from
an admin shell that can write to the PCSX2 app bundle.
TXT
  exit 1
fi

OLD_GUID="$OLD_GUID" GUID="$GUID" perl -0pi -e 's/^.*\Q$ENV{OLD_GUID}\E.*\n//mg; s/^.*\Q$ENV{GUID}\E.*\n//mg' "$PCSX2_DB"

{
  printf '\n# OpenJoystickDriver virtual gamepad\n'
  cat "$OJD_DB"
} >> "$PCSX2_DB"

echo "Installed OpenJoystickDriver mapping into PCSX2."
echo "Backup: $backup"
grep -n "$GUID" "$PCSX2_DB"
