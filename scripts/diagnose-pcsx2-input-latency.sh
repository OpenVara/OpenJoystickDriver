#!/usr/bin/env bash
set -euo pipefail

APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
PCSX2_DB="/Applications/PCSX2.app/Contents/Resources/game_controller_db.txt"

echo "=== OpenJoystickDriver vs SDL3 latency triage ==="
echo

if [[ -x "$APP_BIN" ]]; then
  echo "0) OJD daemon status (shows mode/identity/output):"
  "$APP_BIN" --headless status || true
  echo
  echo "1) Virtual device self-test (press buttons while it runs):"
  "$APP_BIN" --headless selftest 5 || true
  echo
else
  echo "1) SKIP: OpenJoystickDriver not installed at:"
  echo "   $APP_BIN"
  echo "   Fix: build+install the app bundle, then re-run this script."
  echo
fi

echo "2) SDL3 probe (native):"
if [[ -f "$PCSX2_DB" ]]; then
  ./scripts/sdl3-probe.sh --seconds 10 --mappings-file "$PCSX2_DB" || true
else
  ./scripts/sdl3-probe.sh --seconds 10 || true
fi
echo

echo "3) SDL3 probe (PCSX2/Rosetta x86_64, uses PCSX2's bundled SDL3):"
if [[ -f "$PCSX2_DB" ]]; then
  ./scripts/sdl3-probe-pcsx2.sh --seconds 10 --mappings-file "$PCSX2_DB" || true
else
  ./scripts/sdl3-probe-pcsx2.sh --seconds 10 || true
fi
echo

echo "=== What to paste back into chat ==="
echo "- The full output of this script."
echo
echo "=== Fast interpretation ==="
echo "- If (2) sees events instantly but (3) sees 0 devices or very delayed events:"
echo "    -> PCSX2's Intel build / Rosetta SDL path is the bottleneck."
echo "- If both (2) and (3) see events instantly:"
echo "    -> PCSX2 UI/binding layer is the bottleneck."
echo "- If both are delayed:"
echo "    -> OJD's Compatibility device needs changes (descriptor/properties/cadence)."
