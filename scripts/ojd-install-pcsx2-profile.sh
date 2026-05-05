#!/usr/bin/env bash
# Install an OpenJoystickDriver PCSX2 input profile into the user's config.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Resources/PCSX2/OpenJoystickDriver.ini"
PCSX2_DIR="${PCSX2_DIR:-$HOME/Library/Application Support/PCSX2}"
DEST_DIR="$PCSX2_DIR/inputprofiles"
DEST="$DEST_DIR/OpenJoystickDriver.ini"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: missing profile source: $SRC" >&2
  exit 2
fi

mkdir -p "$DEST_DIR"
if [[ -f "$DEST" ]]; then
  cp "$DEST" "$DEST.ojd-backup-$(date +%Y%m%d%H%M%S)"
fi

cp "$SRC" "$DEST"

cat <<TXT
Installed PCSX2 input profile:
  $DEST

In PCSX2, select input profile:
  OpenJoystickDriver

The profile binds both SDL-0 and SDL-1 to Pad 1, so it still works when the
stale DriverKit device occupies one SDL slot before the user-space gamepad.
TXT
