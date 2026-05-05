#!/usr/bin/env bash
# Diagnostics helper for OpenJoystickDriver.
#
# Human-facing entrypoint:
#   ./scripts/ojd diagnose <subcommand>
#
# Subcommands:
#   dext (default), sdl3, pcsx2-latency, backends
#
# Runs all checks regardless of individual failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

die() { echo "ERROR: $*" >&2; exit 2; }

cmd="${1:-dext}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  cat <<'TXT'
Usage:
  ./scripts/ojd diagnose dext
  ./scripts/ojd diagnose sdl3 [--seconds N] [other args]
  ./scripts/ojd diagnose gamecontroller [--seconds N]
  ./scripts/ojd diagnose pcsx2-latency
  ./scripts/ojd diagnose backends [--seconds N]
TXT
  exit 0
fi

run_sdl3_probe_native() {
  local ROOT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  local SRC="$ROOT/tools/sdl3-gamepad-probe/main.c"
  local OUT="/tmp/ojd-sdl3-probe"
  local SDKROOT
  SDKROOT="$(select_macos_sdk)" || return $?

  command -v pkg-config >/dev/null 2>&1 || die "pkg-config not found (brew install pkg-config)"
  pkg-config --exists sdl3 || die "SDL3 not found (brew install sdl3)"
  [[ -f "$SRC" ]] || die "Missing probe source: $SRC"

  echo "Building SDL3 probe (native)..."
  SDKROOT="$SDKROOT" clang -isysroot "$SDKROOT" "$SRC" $(pkg-config --cflags --libs sdl3) -o "$OUT"

  echo
  echo "Running: $OUT $*"
  echo "Tip: if it prints 'Found 0 joystick(s)', grant Input Monitoring to your terminal app:"
  echo "  System Settings -> Privacy & Security -> Input Monitoring"
  echo
  "$OUT" "$@"
}

run_sdl3_probe_pcsx2_x86_64() {
  local PCSX2_APP="/Applications/PCSX2.app"
  local PCSX2_SDL3="$PCSX2_APP/Contents/Frameworks/libSDL3.0.dylib"
  local ROOT SRC OUT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  SRC="$ROOT/tools/sdl3-gamepad-probe/main.c"
  OUT="/tmp/ojd-sdl3-probe-pcsx2-x86_64"
  local SDKROOT
  SDKROOT="$(select_macos_sdk)" || return $?

  [[ -d "$PCSX2_APP" ]] || die "PCSX2 not found at: $PCSX2_APP"
  [[ -f "$PCSX2_SDL3" ]] || die "PCSX2 SDL3 dylib not found at: $PCSX2_SDL3"
  [[ -f "$SRC" ]] || die "Missing probe source: $SRC"

  echo "Building SDL3 probe (PCSX2/Rosetta x86_64)..."
  SDKROOT="$SDKROOT" clang -arch x86_64 -isysroot "$SDKROOT" "$SRC" \
    -I/opt/homebrew/include -I/opt/homebrew/include/SDL3 \
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
}

select_macos_sdk() {
  local sdk
  sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
  if [[ -f "$sdk/usr/include/AvailabilityMacros.h" ]]; then
    echo "$sdk"
    return 0
  fi

  local xcode_dev="/Applications/Xcode_26.3.app/Contents/Developer"
  if [[ -d "$xcode_dev" ]]; then
    sdk="$xcode_dev/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if [[ -f "$sdk/usr/include/AvailabilityMacros.h" ]]; then
      echo "$sdk"
      return 0
    fi
    sdk="$(DEVELOPER_DIR="$xcode_dev" xcrun --show-sdk-path 2>/dev/null || true)"
    if [[ -f "$sdk/usr/include/AvailabilityMacros.h" ]]; then
      echo "$sdk"
      return 0
    fi
  fi

  die "Could not find a macOS SDK with AvailabilityMacros.h"
}

run_limited_command() {
  local limit="$1"
  shift
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= limit )); then
      echo "WARN: timed out after ${limit}s: $*"
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

run_pcsx2_latency_triage() {
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local ROOT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  local CLI_BIN="$ROOT/.build/debug/OpenJoystickDriver"
  if [[ ! -x "$CLI_BIN" ]]; then
    CLI_BIN="$APP_BIN"
  fi
  local PCSX2_DB="/Applications/PCSX2.app/Contents/Resources/game_controller_db.txt"

  echo "=== OpenJoystickDriver vs SDL3 latency triage ==="
  echo

  if [[ -x "$CLI_BIN" ]]; then
    echo "0) OJD daemon status (shows mode/identity/output):"
    run_limited_command 10 "$CLI_BIN" --headless status || true
    echo
    echo "1) Virtual device self-test (press buttons while it runs):"
    run_limited_command 10 "$CLI_BIN" --headless selftest 5 || true
    echo
  else
    echo "1) SKIP: OpenJoystickDriver CLI not found at:"
    echo "   $APP_BIN"
    echo "   Fix: build+install the app bundle, then re-run this script."
    echo
  fi

  echo "2) SDL3 probe (native):"
  if [[ -f "$PCSX2_DB" ]]; then
    run_sdl3_probe_native --seconds 10 --mappings-file "$PCSX2_DB" || true
  else
    run_sdl3_probe_native --seconds 10 || true
  fi
  echo

  echo "3) SDL3 probe (PCSX2/Rosetta x86_64, uses PCSX2's bundled SDL3):"
  if [[ -f "$PCSX2_DB" ]]; then
    run_sdl3_probe_pcsx2_x86_64 --seconds 10 --mappings-file "$PCSX2_DB" || true
  else
    run_sdl3_probe_pcsx2_x86_64 --seconds 10 || true
  fi
}

run_gamecontroller_probe() {
  local seconds="${1:-5}"
  local ROOT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  local PROBE="$ROOT/.build/debug/OpenJoystickDriverGameControllerProbe"

  if [[ ! -x "$PROBE" ]]; then
    echo "Building GameController probe..."
    (cd "$ROOT" && swift build --product OpenJoystickDriverGameControllerProbe)
  fi

  [[ -x "$PROBE" ]] || die "Missing probe binary: $PROBE"
  "$PROBE" --seconds "$seconds"
}

run_backend_acceptance_loop() {
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local ROOT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  local CLI_BIN="$ROOT/.build/debug/OpenJoystickDriver"
  if [[ ! -x "$CLI_BIN" ]]; then
    CLI_BIN="$APP_BIN"
  fi
  local seconds="${1:-5}"
  local step_timeout="$((seconds + 15))"

  echo "=== OpenJoystickDriver backend acceptance loop ==="
  echo

  run_limited() {
    local limit="$1"
    shift
    "$@" &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if (( elapsed >= limit )); then
        echo "WARN: timed out after ${limit}s: $*"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 124
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$pid"
  }

  if [[ -x "$CLI_BIN" ]]; then
    echo "0) CLI status:"
    run_limited "$step_timeout" "$CLI_BIN" --headless status || true
    echo

    echo "1) Output mode:"
    run_limited "$step_timeout" "$CLI_BIN" --headless output status || true
    echo

    echo "2) User-space backend status:"
    run_limited "$step_timeout" "$CLI_BIN" --headless userspace status || true
    echo
  else
    echo "0) SKIP: OpenJoystickDriver CLI not found at:"
    echo "   $APP_BIN"
    echo
  fi

  echo "3) DriverKit backend diagnostics:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" dext || true
  echo

  echo "4) SDL3 consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" sdl3 --seconds "$seconds" || true
  echo

  echo "5) PCSX2/Rosetta consumer probe:"
  if [[ -d "/Applications/PCSX2.app" ]]; then
    run_limited "$step_timeout" run_sdl3_probe_pcsx2_x86_64 --seconds "$seconds" || true
  else
    echo "SKIP: PCSX2 not found at /Applications/PCSX2.app"
  fi
  echo

  echo "6) GameController.framework consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" gamecontroller --seconds "$seconds" || true
}

if [[ "$cmd" == "sdl3" ]]; then
  run_sdl3_probe_native "$@"
  exit 0
fi

if [[ "$cmd" == "gamecontroller" ]]; then
  seconds="5"
  if [[ "${1:-}" == "--seconds" && -n "${2:-}" ]]; then
    seconds="$2"
  fi
  run_gamecontroller_probe "$seconds"
  exit 0
fi

if [[ "$cmd" == "pcsx2-latency" ]]; then
  run_pcsx2_latency_triage
  exit 0
fi

if [[ "$cmd" == "backends" ]]; then
  seconds="5"
  if [[ "${1:-}" == "--seconds" && -n "${2:-}" ]]; then
    seconds="$2"
  fi
  run_backend_acceptance_loop "$seconds"
  exit 0
fi

# cmd == dext falls through to the dext diagnostics implementation below.

# zsh has a 'log' builtin that shadows /usr/bin/log — always use full path
LOG=/usr/bin/log

# Color output when stdout is a terminal
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
ISSUES=()

pass() {
  echo -e "${GREEN}[PASS]${RESET} $1"
  ((PASS_COUNT++)) || true
}

fail() {
  echo -e "${RED}[FAIL]${RESET} $1"
  ((FAIL_COUNT++)) || true
  ISSUES+=("$1")
}

warn() {
  echo -e "${YELLOW}[WARN]${RESET} $1"
  ((WARN_COUNT++)) || true
}

info() {
  echo -e "      $1"
}

BUNDLE_ID="com.openjoystickdriver.VirtualHIDDevice"
DEXT_PROCESS="OpenJoystickVirtualHID"
APP_DEXT_DIR="/Applications/OpenJoystickDriver.app/Contents/Library/SystemExtensions/${BUNDLE_ID}.dext"
DAEMON_LOG="/tmp/com.openjoystickdriver.daemon.out"

echo -e "${BOLD}=== OpenJoystickDriver Dext Diagnostics ===${RESET}"
echo ""

# --- 1. Sysext status ---
sysext_output=$(systemextensionsctl list 2>&1 | grep -i openjoystick || true)
if [[ -n "$sysext_output" ]]; then
  if echo "$sysext_output" | grep -q "activated enabled"; then
    pass "Sysext activated and enabled"
    info "$sysext_output"
  else
    fail "Sysext registered but not fully activated"
    info "$sysext_output"
  fi
else
  fail "Sysext not found — extension not installed"
fi

# --- 2. Installed binary exists ---
INSTALLED_BINARY=""
STALE_BINARIES=()
EXECUTABLE_BINARIES=()
for d in /Library/SystemExtensions/*/; do
  candidate="${d}${BUNDLE_ID}.dext/${DEXT_PROCESS}"
  if [[ -f "$candidate" ]]; then
    if [[ -x "$candidate" ]]; then
      INSTALLED_BINARY="$candidate"
      EXECUTABLE_BINARIES+=("$candidate")
    else
      STALE_BINARIES+=("$candidate")
    fi
  fi
done

if [[ -n "$INSTALLED_BINARY" ]]; then
  pass "Installed binary exists (executable)"
  info "$INSTALLED_BINARY"
elif [[ ${#STALE_BINARIES[@]} -gt 0 ]]; then
  fail "All installed binaries are non-executable (stale sysext state — reboot required)"
  for stale in "${STALE_BINARIES[@]}"; do
    info "  stale: $stale"
  done
else
  fail "Installed binary missing — stale activation (re-run Install Extension)"
fi

if [[ ${#STALE_BINARIES[@]} -gt 0 && -n "$INSTALLED_BINARY" ]]; then
  warn "${#STALE_BINARIES[@]} stale sysext copies found (reboot to clean up)"
  for stale in "${STALE_BINARIES[@]}"; do
    info "  stale: $stale"
  done
fi

if [[ ${#EXECUTABLE_BINARIES[@]} -gt 1 ]]; then
  warn "${#EXECUTABLE_BINARIES[@]} executable sysext copies found"
fi

# --- 3. Installed binary executable ---
if [[ -n "$INSTALLED_BINARY" ]]; then
  pass "Installed binary is executable"
fi

# --- 4. App bundle dext exists ---
if [[ -d "$APP_DEXT_DIR" ]]; then
  pass "App bundle dext present"
  info "$APP_DEXT_DIR"
else
  fail "App bundle dext missing — rebuild the app"
fi

# --- 5. Codesigning valid ---
if [[ -n "$INSTALLED_BINARY" ]]; then
  installed_dext_dir="$(dirname "$INSTALLED_BINARY")"
  if codesign -v "$installed_dext_dir" 2>/dev/null; then
    pass "Installed dext codesign valid"
  else
    fail "Installed dext codesign invalid"
  fi
fi

if [[ -d "$APP_DEXT_DIR" ]]; then
  if codesign -v "$APP_DEXT_DIR" 2>/dev/null; then
    pass "App bundle dext codesign valid"
  else
    fail "App bundle dext codesign invalid"
  fi
fi

# --- 6. Entitlements (DriverKit) ---
check_entitlements() {
  local label="$1" path="$2"
  local ent_output
  ent_output=$(codesign -d --entitlements - "$path" 2>/dev/null || true)
  if echo "$ent_output" | grep -q "com.apple.developer.driverkit"; then
    pass "$label has DriverKit entitlement"
  else
    fail "$label missing DriverKit entitlement"
  fi
}

if [[ -n "$INSTALLED_BINARY" ]]; then
  check_entitlements "Installed dext" "$(dirname "$INSTALLED_BINARY")"
fi
if [[ -d "$APP_DEXT_DIR" ]]; then
  check_entitlements "App bundle dext" "$APP_DEXT_DIR"
fi

# --- 7. Dext process running ---
if pgrep -x "$DEXT_PROCESS" >/dev/null 2>&1; then
  pid=$(pgrep -x "$DEXT_PROCESS")
  pass "Dext process running (PID $pid)"
  running_binary=$(ps -p "$pid" -o args= | awk '{print $1}' || true)
  if [[ -n "$running_binary" ]]; then
    info "process: $running_binary"
    if [[ -n "$INSTALLED_BINARY" && "$running_binary" != "$INSTALLED_BINARY" ]]; then
      fail "Dext process is still running from an older sysext copy"
      info "expected: $INSTALLED_BINARY"
      info "running:  $running_binary"
    fi
  fi
else
  fail "Dext process not running"
fi

# --- 8. IORegistry HID device ---
ioreg_hid=$(ioreg -r -c IOUserHIDDevice 2>/dev/null | grep -i OpenJoystick || true)
if [[ -n "$ioreg_hid" ]]; then
  pass "IORegistry IOUserHIDDevice present"
else
  fail "IORegistry IOUserHIDDevice not found — dext not providing HID service"
fi

# --- 9. IOUserService presence ---
ioreg_service=$(ioreg -l -c IOUserService 2>/dev/null | grep -i openjoystick || true)
if [[ -n "$ioreg_service" ]]; then
  pass "IORegistry IOUserService proxy node present"
else
  fail "IORegistry IOUserService proxy node not found"
fi

# --- 10. Daemon connection ---
if [[ -f "$DAEMON_LOG" ]]; then
  if grep -qE "Connected|Auto-retry connected" "$DAEMON_LOG" 2>/dev/null; then
    pass "Daemon reports connected to dext"
  elif grep -qE "not yet available|not found.*not installed|not approved" "$DAEMON_LOG" 2>/dev/null; then
    fail "Daemon reports dext not yet available"
  else
    warn "Daemon log exists but no connection status found"
  fi
else
  warn "Daemon log not found ($DAEMON_LOG)"
fi

# --- 11. Dext os_log (last 2 minutes) ---
echo ""
echo -e "${BOLD}--- Recent dext logs (last 2m) ---${RESET}"
dext_logs=$($LOG show --last 2m --predicate "process == \"$DEXT_PROCESS\"" --style compact 2>/dev/null | tail -10 || true)
if [[ -n "$dext_logs" ]]; then
  echo "$dext_logs"
else
  echo "  (no dext log entries in the last 2 minutes)"
fi

# --- 12. Kernel DK logs (last 2 minutes) ---
echo ""
echo -e "${BOLD}--- Recent DK kernel logs (last 2m) ---${RESET}"
dk_logs=$($LOG show --last 2m --predicate 'eventMessage contains "DK:"' --style compact 2>/dev/null | tail -10 || true)
if [[ -n "$dk_logs" ]]; then
  echo "$dk_logs"
else
  echo "  (no DK: log entries in the last 2 minutes)"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}=== Summary ===${RESET}"
echo -e "  ${GREEN}$PASS_COUNT passed${RESET}, ${RED}$FAIL_COUNT failed${RESET}, ${YELLOW}$WARN_COUNT warnings${RESET}"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "Issues:"
  for issue in "${ISSUES[@]}"; do
    echo "  - $issue"
  done

  # Suggest most likely root cause
  echo ""
  if printf '%s\n' "${ISSUES[@]}" | grep -q "stale activation"; then
    echo "Most likely: stale sysext — re-activate from the app (Install Extension) or re-run rebuild.sh"
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "not running"; then
    echo "Most likely: dext process crashed or failed to start — check DK logs above"
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "codesign"; then
    echo "Most likely: signing issue — re-sign and re-install the dext"
  fi
fi

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
else
  exit 0
fi
