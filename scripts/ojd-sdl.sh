#!/usr/bin/env bash
# SDL submodule helper for OpenJoystickDriver diagnostics.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SDL_DIR="$PROJECT_DIR/External/SDL"
PATCH_DIR="$PROJECT_DIR/Patches/SDL"
BUILD_DIR="$PROJECT_DIR/.build/sdl-ojd/release"
PREFIX_DIR="$PROJECT_DIR/.build/sdl-ojd/install"
PCSX2_BUILD_DIR="$PROJECT_DIR/.build/sdl-ojd/pcsx2-x86_64"
PCSX2_PREFIX_DIR="$PROJECT_DIR/.build/sdl-ojd/pcsx2/install"

die() { echo "ERROR: $*" >&2; exit 2; }

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd sdl patch                 Apply repo-local SDL patches to External/SDL
  ./scripts/ojd sdl build-patched         Apply patches, then build/install SDL under .build/sdl-ojd/install
  ./scripts/ojd sdl build-pcsx2-patched   Build x86_64 patched SDL for PCSX2 override testing
  ./scripts/ojd sdl pcsx2-override status|install|restore
                                      Temporarily symlink PCSX2 to patched SDL

Notes:
  - External/SDL is a git submodule pinned by the parent repo.
  - SDL changes live as .patch files under Patches/SDL.
USAGE
}

require_submodule() {
  [[ -d "$SDL_DIR/.git" || -f "$SDL_DIR/.git" ]] || die "SDL submodule missing. Run: git submodule update --init --recursive"
}

apply_patch_file() {
  local patch="$1"
  local rel_patch
  rel_patch="$(realpath "$patch")"

  if git -C "$SDL_DIR" apply --check "$rel_patch" >/dev/null 2>&1; then
    echo "Applying $(basename "$patch")"
    git -C "$SDL_DIR" apply "$rel_patch"
    return
  fi
  if git -C "$SDL_DIR" apply --unidiff-zero --check "$rel_patch" >/dev/null 2>&1; then
    echo "Applying $(basename "$patch")"
    git -C "$SDL_DIR" apply --unidiff-zero "$rel_patch"
    return
  fi

  if git -C "$SDL_DIR" apply --reverse --check "$rel_patch" >/dev/null 2>&1; then
    echo "Already applied: $(basename "$patch")"
    return
  fi
  if git -C "$SDL_DIR" apply --unidiff-zero --reverse --check "$rel_patch" >/dev/null 2>&1; then
    echo "Already applied: $(basename "$patch")"
    return
  fi

  die "Patch does not apply cleanly: $patch"
}

apply_patches() {
  require_submodule
  shopt -s nullglob
  local patches=("$PATCH_DIR"/*.patch)
  shopt -u nullglob
  (( ${#patches[@]} > 0 )) || die "No SDL patches found in $PATCH_DIR"

  for patch in "${patches[@]}"; do
    apply_patch_file "$patch"
  done
}

build_patched() {
  apply_patches
  command -v cmake >/dev/null 2>&1 || die "cmake not found"

  cmake -S "$SDL_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF
  cmake --build "$BUILD_DIR" --config Release
  cmake --install "$BUILD_DIR" --config Release

  echo "Patched SDL installed at: $PREFIX_DIR"
}

build_pcsx2_patched() {
  apply_patches
  command -v cmake >/dev/null 2>&1 || die "cmake not found"

  cmake -S "$SDL_DIR" -B "$PCSX2_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PCSX2_PREFIX_DIR" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL=ON \
    -DSDL_HIDAPI_LIBUSB=OFF
  cmake --build "$PCSX2_BUILD_DIR" --config Release --target SDL3-shared
  if ! cmake --install "$PCSX2_BUILD_DIR" --config Release; then
    [[ -f "$PCSX2_PREFIX_DIR/lib/libSDL3.0.dylib" ]] || die "PCSX2 patched SDL install failed before producing $PCSX2_PREFIX_DIR/lib/libSDL3.0.dylib"
    echo "WARN: SDL install reported a non-fatal error after installing libSDL3.0.dylib" >&2
  fi

  [[ -f "$PCSX2_PREFIX_DIR/lib/libSDL3.0.dylib" ]] || die "PCSX2 patched SDL install did not produce $PCSX2_PREFIX_DIR/lib/libSDL3.0.dylib"
  echo "PCSX2 patched SDL installed at: $PCSX2_PREFIX_DIR"
  file "$PCSX2_PREFIX_DIR/lib/libSDL3.0.dylib"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  patch)
    apply_patches
    ;;
  build-patched)
    build_patched
    ;;
  build-pcsx2-patched)
    build_pcsx2_patched
    ;;
  pcsx2-override)
    exec /usr/bin/env bash "$SCRIPT_DIR/ojd-pcsx2-sdl-override.sh" "$@"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    die "Unknown SDL command: $cmd"
    ;;
esac
