#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/tools/sdl3-gamepad-probe/main.c"
OUT="/tmp/ojd-sdl3-probe"

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "ERROR: pkg-config not found."
  echo "Fix: install via Homebrew: brew install pkg-config"
  exit 1
fi

if ! pkg-config --exists sdl3; then
  echo "ERROR: SDL3 not found (pkg-config sdl3 missing)."
  echo "Fix: brew install sdl3"
  exit 1
fi

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: Missing probe source: $SRC"
  exit 1
fi

echo "Building SDL3 probe (native)..."
clang "$SRC" $(pkg-config --cflags --libs sdl3) -o "$OUT"

echo
echo "Running: $OUT $*"
echo "Tip: if it prints 'Found 0 joystick(s)', grant Input Monitoring to your terminal app:"
echo "  System Settings -> Privacy & Security -> Input Monitoring"
echo
"$OUT" "$@"

