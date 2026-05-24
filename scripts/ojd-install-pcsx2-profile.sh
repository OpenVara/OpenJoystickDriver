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

The installed profile uses SDL-0 as a starting point for Pad 1.
If PCSX2 shows multiple OJD SDL instances, rebind/select the OJD controller
that only responds while the PCSX2 window is focused.
TXT
