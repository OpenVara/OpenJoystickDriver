#!/usr/bin/env bash
# Print safe-ish info about a .cer file (DER).
#
# Default output avoids full identifiers. Use --full to print full SHA1/serial.
set -euo pipefail

full=0
if [[ "${1:-}" == "--full" ]]; then
  full=1
  shift
fi

if [[ $# -ne 1 ]]; then
  cat <<'TXT'
Usage:
  ./scripts/cert-info.sh [--full] <cert.cer>

Prints:
  - SHA1 fingerprint
  - serial number
  - Subject OU (Team ID)
  - CN suffix (if present)
TXT
  exit 2
fi

cert="$1"
if [[ ! -f "$cert" ]]; then
  echo "ERROR: missing file: $cert" 1>&2
  exit 1
fi

python3 - "$full" "$cert" <<'PY'
import os, sys, subprocess

full = int(sys.argv[1])
path = sys.argv[2]

def short(s: str) -> str:
    if len(s) <= 12:
        return s
    return s[:8] + "…" + s[-4:]

serial = subprocess.run(
    ["openssl", "x509", "-inform", "DER", "-in", path, "-noout", "-serial"],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    check=True,
).stdout.strip().split("=", 1)[1]

fp = subprocess.run(
    ["openssl", "x509", "-inform", "DER", "-in", path, "-noout", "-fingerprint", "-sha1"],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    check=True,
).stdout.strip().split("=", 1)[1].replace(":", "").lower()

subj = subprocess.run(
    ["openssl", "x509", "-inform", "DER", "-in", path, "-noout", "-subject", "-nameopt", "RFC2253"],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    check=True,
).stdout.strip()

ou = ""
if "OU=" in subj:
    ou = subj.split("OU=", 1)[1].split(",", 1)[0]
cn = ""
if "CN=" in subj:
    cn = subj.split("CN=", 1)[1].split(",", 1)[0]
cn_suffix = "NONE"
if cn.endswith(")") and "(" in cn:
    cn_suffix = cn.rsplit("(", 1)[1].rstrip(")")

print(f"path: {path}")
if full:
    print(f"sha1: {fp}")
    print(f"serial: {serial}")
else:
    print(f"sha1: {short(fp)}  (use --full for full)")
    print(f"serial: {short(serial)}  (use --full for full)")
print(f"ou: {ou}")
print(f"cn_suffix: {cn_suffix}")
PY

