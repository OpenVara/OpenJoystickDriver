#!/usr/bin/env bash
set -euo pipefail

PCSX2_APP="/Applications/PCSX2.app"
PCSX2_SDL3="$PCSX2_APP/Contents/Frameworks/libSDL3.0.dylib"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/tools/sdl3-gamepad-probe/main.c"
OUT="/tmp/ojd-sdl3-probe-pcsx2-x86_64"

if [[ ! -d "$PCSX2_APP" ]]; then
  echo "ERROR: PCSX2 not found at: $PCSX2_APP"
  echo "Fix: install PCSX2 into /Applications, then re-run."
  exit 1
fi

if [[ ! -f "$PCSX2_SDL3" ]]; then
  echo "ERROR: PCSX2 SDL3 dylib not found at: $PCSX2_SDL3"
  exit 1
fi

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: Missing probe source: $SRC"
  exit 1
fi

echo "Building SDL3 probe (PCSX2/Rosetta x86_64)..."
clang -arch x86_64 "$SRC" -I/opt/homebrew/include -I/opt/homebrew/include/SDL3 \
  -L"$PCSX2_APP/Contents/Frameworks" -lSDL3.0 \
  -Wl,-headerpad_max_install_names \
  -o "$OUT"

echo "Patching dylib path so it loads PCSX2's SDL3..."
install_name_tool -change "@executable_path/../Frameworks/libSDL3.0.dylib" "$PCSX2_SDL3" "$OUT" || true

echo
echo "Running: $OUT $*"
echo "Tip: Input Monitoring must be granted to the terminal app you are using."
echo
"$OUT" "$@"

