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

profile="${1:-}"
if [[ -z "$profile" || "${profile:-}" == "-h" || "${profile:-}" == "--help" ]]; then
  cat <<'TXT'
Usage:
  ./scripts/import-embedded-cert-from-profile.sh "<path-to>.provisionprofile"

Example:
  ./scripts/import-embedded-cert-from-profile.sh \
    "$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

After running, verify:
  security find-identity -v -p codesigning
TXT
  exit 2
fi

if [[ ! -f "$profile" ]]; then
  echo "ERROR: missing profile file: $profile" 1>&2
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

