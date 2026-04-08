#!/usr/bin/env bash
# Import the DeveloperCertificates[0] certificate embedded in a provisioning profile into Keychain.
#
# Why:
# - Sometimes the provisioning profile embeds an Apple Development certificate that you *do* have a private key for,
#   but the certificate itself isn't present in Keychain as a "codesigning identity" yet.
# - Importing the embedded cert can cause Keychain to pair it with the existing private key and make the identity usable.
#
# This script does NOT print the certificate contents.
set -euo pipefail

trim_ws() {
  local s="$1"
  # trim leading
  s="${s#"${s%%[!$' \t\r\n']*}"}"
  # trim trailing
  s="${s%"${s##*[!$' \t\r\n']}"}"
  printf '%s' "$s"
}

filtered_args=()
for a in "$@"; do
  t="$(trim_ws "$a")"
  if [[ -n "$t" ]]; then
    filtered_args+=("$t")
  fi
done

profile="${filtered_args[0]:-}"
if [[ -z "$profile" || "${profile:-}" == "-h" || "${profile:-}" == "--help" ]]; then
  cat <<'TXT'
Usage:
  ./scripts/import-embedded-cert-from-profile.sh "<path-to>.provisionprofile"

Example:
  ./scripts/import-embedded-cert-from-profile.sh \
    "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

Common mistake:
  If you type a stray backslash + space (`\ `) you will accidentally pass an extra
  blank argument and this script will treat it as the profile path.
  Fix: run the command on ONE line (copy/paste exactly) with quotes.

After running, verify:
  security find-identity -v -p codesigning
TXT
  exit 2
fi

if [[ ${#filtered_args[@]} -ne 1 ]]; then
  echo "ERROR: expected exactly 1 argument (profile path), got ${#filtered_args[@]}." 1>&2
  echo "Fix: run:" 1>&2
  echo "  ./scripts/import-embedded-cert-from-profile.sh \"$profile\"" 1>&2
  exit 2
fi

if [[ ! -f "$profile" ]]; then
  echo "ERROR: missing profile file: $profile" 1>&2
  echo "" 1>&2
  echo "Fix: check what profiles you actually have installed:" 1>&2
  echo "  ls -la \"$HOME/Library/MobileDevice/Provisioning Profiles\" | sed -n '1,80p'" 1>&2
  echo "" 1>&2
  echo "If the file exists there, re-run with that exact path in quotes." 1>&2
  exit 1
fi

tmp="/tmp/ojd-embedded-devcert.der"

python3 - "$profile" "$tmp" <<'PY'
import os, sys, plistlib, subprocess

profile = os.path.expanduser(sys.argv[1])
out_path = sys.argv[2]

def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return p.stdout if (p.returncode == 0 and p.stdout) else b""

raw = decode(profile)
if not raw or b"<?xml" not in raw:
    raise SystemExit("ERROR: could not decode provisioning profile")
raw = raw[raw.index(b"<?xml") :]
obj = plistlib.loads(raw)
certs = obj.get("DeveloperCertificates") or []
if not certs or not isinstance(certs[0], (bytes, bytearray)):
    raise SystemExit("ERROR: profile has no DeveloperCertificates[0]")

with open(out_path, "wb") as f:
    f.write(certs[0])
PY

echo "Extracted embedded certificate to: $tmp"
echo "Importing into login keychain (Keychain may prompt)…"
security import "$tmp" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
echo "Done."
echo ""
echo "Now run:"
echo "  security find-identity -v -p codesigning"
