#!/usr/bin/env bash
# Install provisioning profiles into ~/Library/MobileDevice/Provisioning Profiles/
#
# Source profiles are expected in ~/Documents/Profiles or ~/Documents/profiles.
# This script copies only the canonical filenames the repo expects.
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  if [[ -d "$HOME/Documents/Profiles" ]]; then
    SRC="$HOME/Documents/Profiles"
  else
    SRC="$HOME/Documents/profiles"
  fi
fi

DST="$HOME/Library/MobileDevice/Provisioning Profiles"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: Source directory not found: $SRC"
  echo "Expected: $HOME/Documents/Profiles or $HOME/Documents/profiles"
  exit 1
fi

mkdir -p "$DST"

copy_one() {
  local name="$1"
  local src_path="$SRC/$name"
  if [[ ! -f "$src_path" ]]; then
    echo "ERROR: Missing profile: $src_path"
    exit 1
  fi
  cp -f "$src_path" "$DST/"
}

copy_one "OpenJoystickDriver.provisionprofile"
copy_one "OpenJoystickDriver_DevID.provisionprofile"
copy_one "OpenJoystickDriverDaemon.provisionprofile"
copy_one "OpenJoystickDriverDaemon_DevID.provisionprofile"
copy_one "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

echo "Installed profiles to: $DST"
ls -la "$DST" | awk '/OpenJoystickDriver/ {print "  " $9}'

