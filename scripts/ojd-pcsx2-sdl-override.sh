#!/usr/bin/env bash
# Temporarily replace PCSX2's bundled SDL3 dylib with OJD's patched SDL build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PCSX2_APP="${PCSX2_APP:-/Applications/PCSX2.app}"
PCSX2_SDL="$PCSX2_APP/Contents/Frameworks/libSDL3.0.dylib"
BACKUP="$PCSX2_SDL.ojd-original"
PATCHED_SDL="${OJD_PCSX2_PATCHED_SDL:-$ROOT/.build/sdl-ojd/pcsx2/install/lib/libSDL3.0.dylib}"
CLONE_APP="${OJD_PCSX2_OVERRIDE_APP:-/private/tmp/PCSX2-OJD.app}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd sdl pcsx2-override status
  ./scripts/ojd sdl pcsx2-override install
  ./scripts/ojd sdl pcsx2-override restore
  ./scripts/ojd sdl pcsx2-override clone-install

This is a temporary local experiment. install moves PCSX2's bundled
libSDL3.0.dylib aside to libSDL3.0.dylib.ojd-original and symlinks in OJD's
patched SDL build. If /Applications/PCSX2.app cannot be modified, clone-install
creates a writable /private/tmp/PCSX2-OJD.app copy, copies in patched SDL, strips
quarantine, and ad-hoc signs the clone.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 2; }

require_pcsx2() {
  [[ -d "$PCSX2_APP" ]] || die "PCSX2 app not found: $PCSX2_APP"
  [[ -e "$PCSX2_SDL" || -e "$BACKUP" ]] || die "PCSX2 SDL dylib not found: $PCSX2_SDL"
}

require_patched_sdl() {
  [[ -f "$PATCHED_SDL" ]] || die "Patched x86_64 SDL not found: $PATCHED_SDL (run: ./scripts/ojd sdl build-pcsx2-patched)"
  if command -v lipo >/dev/null 2>&1; then
    lipo -archs "$PATCHED_SDL" | grep -qw x86_64 || die "Patched SDL is not x86_64-compatible: $PATCHED_SDL"
  else
    file "$PATCHED_SDL" | grep -q x86_64 || die "Patched SDL is not x86_64-compatible: $PATCHED_SDL"
  fi
}

status() {
  require_pcsx2
  echo "PCSX2 SDL: $PCSX2_SDL"
  if [[ -L "$PCSX2_SDL" ]]; then
    echo "override: symlink -> $(readlink "$PCSX2_SDL")"
  elif [[ -f "$BACKUP" && -f "$PCSX2_SDL" ]]; then
    echo "override: copied patched dylib installed (backup present)"
  elif [[ -f "$PCSX2_SDL" ]]; then
    echo "override: not installed (regular bundled dylib present)"
  else
    echo "override: missing active dylib"
  fi
  if [[ -f "$BACKUP" ]]; then
    echo "backup: $BACKUP"
  else
    echo "backup: missing"
  fi
  if [[ -f "$PATCHED_SDL" ]]; then
    echo "patched: $PATCHED_SDL ($(file -b "$PATCHED_SDL"))"
  else
    echo "patched: missing ($PATCHED_SDL)"
  fi
}

sanitize_and_sign_clone() {
  # A modified quarantined app reports as “damaged”; strip copied quarantine and
  # ad-hoc sign the clone after replacing SDL.
  xattr -cr "$PCSX2_APP" 2>/dev/null || true
  codesign --force --deep --sign - "$PCSX2_APP" >/dev/null
  codesign --verify --deep --strict --verbose=2 "$PCSX2_APP" >/dev/null
}

install_copy_override() {
  require_pcsx2
  require_patched_sdl
  if [[ ! -f "$BACKUP" ]]; then
    [[ -f "$PCSX2_SDL" ]] || die "Cannot back up missing PCSX2 SDL: $PCSX2_SDL"
    mv "$PCSX2_SDL" "$BACKUP"
  fi
  rm -f "$PCSX2_SDL"
  cp "$PATCHED_SDL" "$PCSX2_SDL"
  echo "Installed PCSX2 SDL copy override: $PCSX2_SDL <= $PATCHED_SDL"
}

install_override() {
  require_pcsx2
  require_patched_sdl
  if [[ -L "$PCSX2_SDL" ]]; then
    local current
    current="$(readlink "$PCSX2_SDL")"
    if [[ "$current" == "$PATCHED_SDL" ]]; then
      echo "PCSX2 SDL override already installed: $PCSX2_SDL -> $PATCHED_SDL"
      return 0
    fi
    die "PCSX2 SDL is already a different symlink: $PCSX2_SDL -> $current"
  fi
  if [[ ! -f "$BACKUP" ]]; then
    [[ -f "$PCSX2_SDL" ]] || die "Cannot back up missing PCSX2 SDL: $PCSX2_SDL"
    mv "$PCSX2_SDL" "$BACKUP"
  else
    [[ ! -e "$PCSX2_SDL" ]] || die "Backup exists and active SDL also exists; refusing to overwrite either"
  fi
  ln -s "$PATCHED_SDL" "$PCSX2_SDL"
  echo "Installed PCSX2 SDL override: $PCSX2_SDL -> $PATCHED_SDL"
}

restore_override() {
  require_pcsx2
  if [[ -L "$PCSX2_SDL" ]]; then
    rm "$PCSX2_SDL"
  elif [[ -e "$PCSX2_SDL" ]]; then
    die "Active PCSX2 SDL is not a symlink; refusing to remove: $PCSX2_SDL"
  fi
  [[ -f "$BACKUP" ]] || die "Backup missing: $BACKUP"
  mv "$BACKUP" "$PCSX2_SDL"
  echo "Restored original PCSX2 SDL: $PCSX2_SDL"
}

clone_install() {
  [[ -d "$PCSX2_APP" ]] || die "Source PCSX2 app not found: $PCSX2_APP"
  require_patched_sdl
  if [[ -e "$CLONE_APP" ]]; then
    case "$CLONE_APP" in
      /private/tmp/PCSX2-OJD.app|/tmp/PCSX2-OJD.app) rm -rf "$CLONE_APP" ;;
      *) die "Refusing to remove non-default clone path: $CLONE_APP" ;;
    esac
  fi
  ditto --noextattr --noqtn "$PCSX2_APP" "$CLONE_APP"
  PCSX2_APP="$CLONE_APP"
  PCSX2_SDL="$PCSX2_APP/Contents/Frameworks/libSDL3.0.dylib"
  BACKUP="$PCSX2_SDL.ojd-original"
  install_copy_override
  sanitize_and_sign_clone
  echo "Launch test copy with:"
  echo "  open '$CLONE_APP'"
}

cmd="${1:-status}"
case "$cmd" in
  status) status ;;
  install) install_override ;;
  restore) restore_override ;;
  clone-install) clone_install ;;
  -h|--help|help) usage ;;
  *) die "Unknown command: $cmd" ;;
esac
