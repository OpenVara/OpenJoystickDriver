#!/usr/bin/env bash
# Repair stale OpenJoystickDriver DriverKit process state.

set -euo pipefail

DEXT_ID="com.openjoystickdriver.VirtualHIDDevice"
PROCESS_NAME="OpenJoystickVirtualHID"

die() { echo "ERROR: $*" >&2; exit 2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "DriverKit repair is macOS-only"
fi

expected_path="$(
  find /Library/SystemExtensions -path "*/${DEXT_ID}.dext/${PROCESS_NAME}" -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1
)"

if [[ -z "$expected_path" ]]; then
  die "No installed ${DEXT_ID} binary found in /Library/SystemExtensions"
fi

echo "Expected active dext binary:"
echo "  $expected_path"
echo

found_stale=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%% *}"
  path="${line#* }"
  if [[ "$path" == "$expected_path"* ]]; then
    echo "Active dext process is already on expected path:"
    echo "  pid=$pid $path"
    continue
  fi

  found_stale=1
  echo "Killing stale dext process:"
  echo "  pid=$pid $path"
  sudo kill -9 "$pid"
done < <(
  ps -axo pid=,command= \
    | awk -v name="$PROCESS_NAME" -v id="$DEXT_ID" '$0 ~ name && $0 ~ id {pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); print pid " " $0}'
)

if [[ "$found_stale" == "0" ]]; then
  echo "No stale dext process found."
fi

echo
echo "Waiting for macOS to settle DriverKit process state..."
sleep 2

echo
echo "Current OpenJoystickDriver system extensions:"
systemextensionsctl list 2>&1 | grep "$DEXT_ID" || true

echo
echo "Current dext processes:"
ps -axo pid=,command= | grep "$PROCESS_NAME" | grep "$DEXT_ID" | grep -v grep || true
