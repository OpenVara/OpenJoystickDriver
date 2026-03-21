#!/usr/bin/env bash
# Diagnose DriverKit extension state: activation, binaries, signing, IORegistry.
# Runs all checks regardless of individual failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

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
for d in /Library/SystemExtensions/*/; do
  candidate="${d}${BUNDLE_ID}.dext/${DEXT_PROCESS}"
  if [[ -f "$candidate" ]]; then
    if [[ -x "$candidate" ]]; then
      INSTALLED_BINARY="$candidate"
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
