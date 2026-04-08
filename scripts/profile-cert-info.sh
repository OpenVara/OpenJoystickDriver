#!/usr/bin/env bash
# Print safe-ish information about the certificate embedded in a provisioning profile.
#
# Default output avoids full identifiers. Use --full to print full SHA1/serial.
set -euo pipefail

full=0
if [[ "${1:-}" == "--full" ]]; then
  full=1
  shift
fi

if [[ $# -lt 1 ]]; then
  cat <<'TXT'
Usage:
  ./scripts/profile-cert-info.sh [--full] <profile1.provisionprofile> [profile2...]

Prints:
  - profile name + TeamIdentifier
  - embedded cert SHA1 + serial + OU (team) + CN suffix (if present)

Notes:
  - Team ID is the certificate Subject OU and profile TeamIdentifier.
  - The display-name "(XXXXXXXXXX)" suffix is NOT a reliable Team ID.
TXT
  exit 2
fi

python3 - "$full" "$@" <<'PY'
import os, sys, plistlib, subprocess, tempfile

full = int(sys.argv[1])
profiles = sys.argv[2:]

def decode_profile(path: str) -> bytes:
    p = subprocess.run(["security", "cms", "-D", "-i", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return p.stdout if (p.returncode == 0 and p.stdout) else b""

def sha1_of_der(der: bytes) -> str:
    out = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-fingerprint", "-sha1"],
        input=der,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=True,
    ).stdout.strip()
    # "sha1 Fingerprint=AA:BB:..."
    return out.split("=", 1)[1].replace(":", "").lower()

def serial_of_der(der: bytes) -> str:
    out = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-serial"],
        input=der,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=True,
    ).stdout.strip()
    return out.split("=", 1)[1]

def subject_rfc2253_of_der(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der)
        tmp = f.name
    try:
        return subprocess.run(
            ["openssl", "x509", "-inform", "DER", "-in", tmp, "-noout", "-subject", "-nameopt", "RFC2253"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=True,
        ).stdout.strip()
    finally:
        try: os.unlink(tmp)
        except OSError: pass

def short(s: str) -> str:
    if len(s) <= 12:
        return s
    return s[:8] + "…" + s[-4:]

for path in profiles:
    path = os.path.expanduser(path)
    base = os.path.basename(path)
    print(f"==> {base}")

    if not os.path.isfile(path):
        print("  error: missing file")
        continue

    try:
        raw = decode_profile(path)
        if not raw or b"<?xml" not in raw:
            raise RuntimeError("decode failed")
        raw = raw[raw.index(b"<?xml") :]
        obj = plistlib.loads(raw)
    except Exception:
        print("  error: could not decode profile")
        continue

    name = obj.get("Name") if isinstance(obj.get("Name"), str) else "UNKNOWN"
    team = "UNKNOWN"
    ti = obj.get("TeamIdentifier") or []
    if isinstance(ti, list) and ti and isinstance(ti[0], str):
        team = ti[0]

    print(f"  name: {name}")
    print(f"  team_identifier: {team}")

    certs = obj.get("DeveloperCertificates") or []
    if not certs or not isinstance(certs[0], (bytes, bytearray)):
        print("  embedded_cert: missing")
        continue

    der = certs[0]
    sha1 = sha1_of_der(der)
    serial = serial_of_der(der)
    subj = subject_rfc2253_of_der(der)

    ou = ""
    if "OU=" in subj:
        ou = subj.split("OU=", 1)[1].split(",", 1)[0]
    cn = ""
    if "CN=" in subj:
        cn = subj.split("CN=", 1)[1].split(",", 1)[0]
    cn_suffix = "NONE"
    if cn.endswith(")") and "(" in cn:
        cn_suffix = cn.rsplit("(", 1)[1].rstrip(")")

    if full:
        print(f"  embedded_cert_sha1: {sha1}")
        print(f"  embedded_cert_serial: {serial}")
    else:
        print(f"  embedded_cert_sha1: {short(sha1)}  (use --full for full)")
        print(f"  embedded_cert_serial: {short(serial)}  (use --full for full)")
    print(f"  embedded_cert_ou: {ou}")
    print(f"  embedded_cert_cn_suffix: {cn_suffix}")
PY

