#!/usr/bin/env bash
# Diagnose signing + provisioning setup without printing sensitive identifiers.
#
# This script is intentionally "simpleton-adjacent":
# - tells you what is wrong
# - tells you exactly what to click/run next
#
# It avoids printing:
# - Apple ID email
# - full certificate subjects
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

say() { printf '%s\n' "$*"; }
hr() { say ""; say "------------------------------------------------------------"; }

KEYCHAINS_DIR="$HOME/Library/Keychains"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

mode_octal() {
  python3 - "$1" <<'PY' 2>/dev/null || echo "UNKNOWN"
import os, stat, sys
p=sys.argv[1]
try:
  m=stat.S_IMODE(os.stat(p).st_mode)
  print(format(m, "03o"))
except Exception:
  print("UNKNOWN")
PY
}

check_keychain_permissions() {
  hr
  say "Keychain file permissions"

  if [[ ! -d "$KEYCHAINS_DIR" ]]; then
    say "ERROR: missing: $KEYCHAINS_DIR"
    return 1
  fi
  if [[ ! -f "$LOGIN_KEYCHAIN" ]]; then
    say "ERROR: missing: $LOGIN_KEYCHAIN"
    return 1
  fi

  local dir_mode file_mode
  dir_mode="$(mode_octal "$KEYCHAINS_DIR")"
  file_mode="$(mode_octal "$LOGIN_KEYCHAIN")"

  say "  $KEYCHAINS_DIR mode: $dir_mode (expected 700)"
  say "  $LOGIN_KEYCHAIN mode: $file_mode (expected 600)"

  if [[ "$dir_mode" != "700" || "$file_mode" != "600" ]]; then
    say ""
    say "FIX:"
    say "  chmod 700 \"$KEYCHAINS_DIR\""
    say "  chmod 600 \"$LOGIN_KEYCHAIN\""
    say "  # then log out/in (or reboot)"
  else
    say "OK"
  fi
}

list_identities() {
  hr
  say "Code-signing identities (via security)"
  local out
  out="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if echo "$out" | grep -q "0 valid identities found"; then
    say "ERROR: 0 valid identities found"
    say ""
    say "Fix checklist:"
    say "  - Keychain Access → login → My Certificates: cert MUST have a private key under it"
    say "  - Keychain permissions (see section above)"
    say "  - Import Apple intermediates (WWDR + DeveloperIDG2CA)"
    return 1
  fi

  # Print only SHA1 + kind, not the full subject string.
  echo "$out" | while IFS= read -r line; do
    if [[ "$line" =~ \"Apple\ Development: ]]; then
      sha="$(echo "$line" | awk '{print $2}')"
      say "  Apple Development SHA1: ${sha}"
    elif [[ "$line" =~ \"Developer\ ID\ Application: ]]; then
      sha="$(echo "$line" | awk '{print $2}')"
      say "  Developer ID App SHA1:  ${sha}"
    fi
  done
}

profile_sha1() {
  local profile="$1"
  python3 - "$profile" <<'PY'
import os, sys, plistlib, subprocess
p = sys.argv[1]
out = subprocess.check_output(["openssl","smime","-inform","der","-verify","-noverify","-in",p], stderr=subprocess.DEVNULL)
obj = plistlib.loads(out)
cert = obj.get("DeveloperCertificates",[b""])[0]
fp = subprocess.check_output(["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"], input=cert, stderr=subprocess.DEVNULL).decode().strip()
print(fp.split("=",1)[1].replace(":","").lower())
PY
}

profile_team() {
  local profile="$1"
  python3 - "$profile" <<'PY'
import os, sys, plistlib, subprocess
p = sys.argv[1]
out = subprocess.check_output(["openssl","smime","-inform","der","-verify","-noverify","-in",p], stderr=subprocess.DEVNULL)
obj = plistlib.loads(out)
team = (obj.get("TeamIdentifier") or ["UNKNOWN"])[0]
print(team if team else "UNKNOWN")
PY
}

profile_name() {
  local profile="$1"
  python3 - "$profile" <<'PY'
import os, sys, plistlib, subprocess
p = sys.argv[1]
out = subprocess.check_output(["openssl","smime","-inform","der","-verify","-noverify","-in",p], stderr=subprocess.DEVNULL)
obj = plistlib.loads(out)
name = obj.get("Name") or ""
print(name if isinstance(name,str) and name else "UNKNOWN")
PY
}

profile_has_entitlement() {
  local profile="$1"
  local key="$2"
  python3 - "$profile" "$key" <<'PY'
import os, sys, plistlib, subprocess
p, k = sys.argv[1], sys.argv[2]
out = subprocess.check_output(["openssl","smime","-inform","der","-verify","-noverify","-in",p], stderr=subprocess.DEVNULL)
obj = plistlib.loads(out)
ent = obj.get("Entitlements") or {}
print("true" if k in ent else "false")
PY
}

check_profiles() {
  hr
  say "Provisioning profiles (installed)"

  local prof_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  if [[ ! -d "$prof_dir" ]]; then
    say "ERROR: missing: $prof_dir"
    say "Fix: ./scripts/install-profiles.sh \"$HOME/Documents/Profiles\""
    return 1
  fi

  local GUI_DEV="$prof_dir/OpenJoystickDriver.provisionprofile"
  local GUI_DEVID="$prof_dir/OpenJoystickDriver_DevID.provisionprofile"
  local DAEMON_DEV="$prof_dir/OpenJoystickDriverDaemon.provisionprofile"
  local DAEMON_DEVID="$prof_dir/OpenJoystickDriverDaemon_DevID.provisionprofile"
  local DEXT="$prof_dir/OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

  local any_missing=0
  for p in "$GUI_DEV" "$GUI_DEVID" "$DAEMON_DEV" "$DAEMON_DEVID" "$DEXT"; do
    if [[ ! -f "$p" ]]; then
      say "ERROR: missing: $p"
      any_missing=1
    fi
  done
  [[ "$any_missing" -eq 0 ]] || return 1

  say "  GUI dev:    $(profile_name "$GUI_DEV")"
  say "  GUI DevID:  $(profile_name "$GUI_DEVID")"
  say "  Daemon dev: $(profile_name "$DAEMON_DEV")"
  say "  Daemon DevID: $(profile_name "$DAEMON_DEVID")"
  say "  Dext:       $(profile_name "$DEXT")"

  # `com.apple.developer.hid.virtual.device` is required by the process that creates IOHIDUserDevice:
  # - daemon (normal path), and/or
  # - GUI app (embedded fallback path).
  local ent="com.apple.developer.hid.virtual.device"
  local gui_dev_has gui_devid_has daemon_dev_has daemon_devid_has
  gui_dev_has="$(profile_has_entitlement "$GUI_DEV" "$ent")"
  gui_devid_has="$(profile_has_entitlement "$GUI_DEVID" "$ent")"
  daemon_dev_has="$(profile_has_entitlement "$DAEMON_DEV" "$ent")"
  daemon_devid_has="$(profile_has_entitlement "$DAEMON_DEVID" "$ent")"
  say "  hid.virtual.device (GUI dev):     $gui_dev_has"
  say "  hid.virtual.device (GUI DevID):   $gui_devid_has"
  say "  hid.virtual.device (Daemon dev):  $daemon_dev_has"
  say "  hid.virtual.device (Daemon DevID): $daemon_devid_has"
  if [[ "$daemon_dev_has" != "true" || "$daemon_devid_has" != "true" || "$gui_dev_has" != "true" ]]; then
    say ""
    say "WARN: Compatibility mode (user-space virtual gamepad) may not work."
    say "Fix: enable entitlement 'com.apple.developer.hid.virtual.device' on:"
    say "  - Identifier com.openjoystickdriver.daemon (daemon)"
    say "  - Identifier com.openjoystickdriver (GUI app) if using embedded fallback"
    say "Then regenerate + re-install the relevant provisioning profiles."
  fi

  # Compare embedded cert SHA1s to identities in Keychain (by SHA1).
  local want_apple want_devid
  want_apple="$(profile_sha1 "$DEXT")"
  want_devid="$(profile_sha1 "$GUI_DEVID")"

  local out
  out="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if echo "$out" | grep -q "0 valid identities found"; then
    say ""
    say "ERROR: 0 valid identities; cannot verify profile-to-keychain match."
    return 1
  fi

  local have_apple_sha1s have_devid_sha1s
  have_apple_sha1s="$(echo "$out" | awk '/"Apple Development:/{print $2}' | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"
  have_devid_sha1s="$(echo "$out" | awk '/"Developer ID Application:/{print $2}' | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"

  say ""
  say "Profile ↔ Keychain match"
  say "  Dext embedded AppleDev SHA1:  $want_apple"
  if echo " $have_apple_sha1s " | grep -q " $want_apple "; then
    say "  Apple Development identity:  OK"
  else
    say "  Apple Development identity:  MISMATCH"
    say "  Fix: regenerate the DEXT profile selecting the Apple Development certificate you have in Keychain."
  fi

  say "  GUI embedded DevID SHA1:     $want_devid"
  if echo " $have_devid_sha1s " | grep -q " $want_devid "; then
    say "  Developer ID identity:       OK"
  else
    say "  Developer ID identity:       MISMATCH"
    say "  Fix: regenerate GUI/daemon DevID profiles selecting the Developer ID certificate you have in Keychain."
  fi
}

main() {
  say "OpenJoystickDriver signing doctor"
  check_keychain_permissions || true
  list_identities || true
  check_profiles || true
  hr
  say "Next steps"
  say "  1) ./scripts/configure-signing.sh"
  say "  2) ./scripts/build-dev.sh"
  say "  3) ./scripts/build-dext.sh"
}

main "$@"
