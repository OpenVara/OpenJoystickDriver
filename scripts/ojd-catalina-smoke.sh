#!/usr/bin/env bash
# Smoke-test an OpenJoystickDriver.app bundle on macOS 10.15.
set -euo pipefail

APP_PATH="/Applications/OpenJoystickDriver.app"
RUN_INSTALL=0
LABEL="com.openjoystickdriver.daemon"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ojd diagnose catalina [app-path] [--install]

Checks the app bundle copied to a macOS 10.15 machine. By default this is
read-only. Pass --install to run the app's LaunchAgent registration path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      RUN_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      APP_PATH="$1"
      shift
      ;;
  esac
done

failures=0

pass() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; failures=$((failures + 1)); }
note() { echo "[INFO] $*"; }

require_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    pass "found $path"
  else
    fail "missing $path"
  fi
}

plist_value() {
  local key="$1" plist="$2"
  /usr/bin/plutil -extract "$key" raw "$plist" 2>/dev/null || true
}

archs_for() {
  /usr/bin/lipo -info "$1" 2>/dev/null | sed 's/^.* are: //;s/^.* architecture: //'
}

min_macos_for() {
  /usr/bin/otool -l "$1" 2>/dev/null | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build = 1; in_min = 0; next }
    in_build && $1 == "minos" { print $2; exit }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { in_min = 1; in_build = 0; next }
    in_min && $1 == "version" { print $2; exit }
  ' || true
}

check_binary() {
  local label="$1" path="$2"
  require_file "$path"
  [[ -f "$path" ]] || return

  local archs minos
  archs="$(archs_for "$path")"
  note "$label archs: $archs"
  if [[ "$archs" == *"x86_64"* ]]; then
    pass "$label contains x86_64"
  else
    fail "$label missing x86_64"
  fi

  minos="$(min_macos_for "$path")"
  note "$label min macOS: ${minos:-unknown}"
  if [[ "$minos" == "10.15" ]]; then
    pass "$label targets macOS 10.15"
  else
    fail "$label does not report macOS 10.15 minimum"
  fi
}

echo "OpenJoystickDriver Catalina smoke test"
echo "app: $APP_PATH"
echo "host macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
echo ""

INFO_PLIST="$APP_PATH/Contents/Info.plist"
GUI_BIN="$APP_PATH/Contents/MacOS/OpenJoystickDriver"
DAEMON_BIN="$APP_PATH/Contents/MacOS/OpenJoystickDriverDaemon"
DAEMON_APP_BIN="$APP_PATH/Contents/MacOS/OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
ICON="$APP_PATH/Contents/Resources/OpenJoystickDriver.icns"
AGENT_PLIST="$APP_PATH/Contents/Library/LaunchAgents/$LABEL.plist"

if [[ ! -d "$APP_PATH" ]]; then
  fail "app bundle not found: $APP_PATH"
  exit 1
fi

require_file "$INFO_PLIST"
require_file "$ICON"
require_file "$AGENT_PLIST"

minimum="$(plist_value LSMinimumSystemVersion "$INFO_PLIST")"
icon_name="$(plist_value CFBundleIconFile "$INFO_PLIST")"
note "LSMinimumSystemVersion: ${minimum:-missing}"
note "CFBundleIconFile: ${icon_name:-missing}"
[[ "$minimum" == "10.15" ]] || fail "LSMinimumSystemVersion is not 10.15"
[[ "$icon_name" == "OpenJoystickDriver" ]] || fail "CFBundleIconFile is not OpenJoystickDriver"

check_binary "GUI" "$GUI_BIN"
check_binary "daemon" "$DAEMON_BIN"
check_binary "nested daemon app" "$DAEMON_APP_BIN"

echo ""
note "headless status:"
"$GUI_BIN" --headless status || fail "headless status failed"

if [[ "$RUN_INSTALL" -eq 1 ]]; then
  echo ""
  if [[ "$APP_PATH" != "/Applications/OpenJoystickDriver.app" ]]; then
    fail "--install requires /Applications/OpenJoystickDriver.app"
  else
    note "installing LaunchAgent"
    "$GUI_BIN" --headless install || fail "headless install failed"
    /bin/launchctl print "gui/$(/usr/bin/id -u)/$LABEL" >/tmp/ojd-catalina-launchctl.txt 2>&1 \
      && pass "launchctl print succeeded" \
      || fail "launchctl print failed; see /tmp/ojd-catalina-launchctl.txt"
  fi
else
  note "skipping LaunchAgent mutation; pass --install to test registration"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
  pass "Catalina smoke checks passed"
else
  fail "$failures check(s) failed"
fi
exit "$failures"
