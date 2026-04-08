#!/usr/bin/env bash
# Signing helper for OpenJoystickDriver.
#
# Human-facing entrypoint:
#   ./scripts/ojd signing <subcommand>
#
# Default behavior (no args): generates `scripts/.env.dev` and `scripts/.env.release`.
#
# Goals:
# - No manual copy/paste of identities or Team IDs
# - Avoid heredoc pitfalls when pasting into wrapped terminals
# - Keep output non-sensitive (does not print identity strings)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

die() { echo "ERROR: $*" >&2; exit 2; }

cmd="${1:-configure}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  cat <<'TXT'
Usage:
  ./scripts/ojd signing install-profiles [~/Documents/Profiles]
  ./scripts/ojd signing configure
  ./scripts/ojd signing doctor
  ./scripts/ojd signing audit [paths...]
  ./scripts/ojd signing cert-info [--full] <cert.cer>
  ./scripts/ojd signing profile-info [--full] <profile1.provisionprofile> [profile2...]
  ./scripts/ojd signing import-embedded <profile.provisionprofile>
TXT
  exit 0
fi

cmd_install_profiles() {
  local SRC="${1:-}"
  if [[ -z "$SRC" ]]; then
    if [[ -d "$HOME/Documents/Profiles" ]]; then
      SRC="$HOME/Documents/Profiles"
    else
      SRC="$HOME/Documents/profiles"
    fi
  fi
  local DST="$HOME/Library/MobileDevice/Provisioning Profiles"
  [[ -d "$SRC" ]] || die "Source directory not found: $SRC (expected ~/Documents/Profiles)"
  mkdir -p "$DST"

  copy_one() {
    local name="$1"
    local src_path="$SRC/$name"
    [[ -f "$src_path" ]] || die "Missing profile: $src_path"
    cp -f "$src_path" "$DST/"
  }

  copy_one "OpenJoystickDriver.provisionprofile"
  copy_one "OpenJoystickDriver_DevID.provisionprofile"
  copy_one "OpenJoystickDriverDaemon.provisionprofile"
  copy_one "OpenJoystickDriverDaemon_DevID.provisionprofile"
  copy_one "OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

  echo "Installed profiles to: $DST"
  ls -la "$DST" | awk '/OpenJoystickDriver/ {print "  " $9}'
}

cmd_audit() {
  decode_profile() {
    local profile="$1"
    if security cms -D -i "$profile" 2>/dev/null; then
      return 0
    fi
    openssl smime -inform der -verify -noverify -in "$profile" 2>/dev/null
  }

  collect_profiles() {
    if [[ $# -gt 0 ]]; then
      printf '%s\n' "$@"
      return 0
    fi

    local found=0
    for d in "$HOME/Documents/profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
      if [[ -d "$d" ]]; then
        found=1
        find "$d" -maxdepth 1 -type f \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) -print 2>/dev/null || true
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo "No profile directories found under:" 1>&2
      echo "  - $HOME/Documents/profiles" 1>&2
      echo "  - $HOME/Library/MobileDevice/Provisioning Profiles" 1>&2
    fi
  }

  audit_one() {
    local profile="$1"
    python3 - "$profile" <<'PY'
import os, sys, plistlib, subprocess, tempfile
profile = sys.argv[1]
def decode_profile(path: str) -> bytes:
    p = subprocess.run(['bash','-lc', f'decode_profile {path!r}'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError("decode failed")
    return p.stdout
def classify_cert_kind(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(prefix='ojd_cert_', suffix='.der', delete=True) as tf:
        tf.write(der); tf.flush()
        p = subprocess.run(['openssl','x509','-inform','DER','-in',tf.name,'-noout','-subject'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode != 0:
            return "UNKNOWN"
        subj = p.stdout.decode('utf-8','replace')
        if 'CN=' not in subj:
            return "UNKNOWN"
        cn = subj.split('CN=',1)[1].split('\n',1)[0]
        cn = cn.split('/',1)[0].strip()
        return cn.split(':',1)[0] if ':' in cn else cn
try:
    plist_bytes = decode_profile(profile)
    obj = plistlib.loads(plist_bytes)
except Exception:
    print(f"==> {os.path.basename(profile)}")
    print("  decode_ok: false")
    sys.exit(0)
ent = obj.get('Entitlements', {}) or {}
app_id = ent.get('com.apple.application-identifier') or ent.get('application-identifier')
bundle_suffix = "UNKNOWN"
if isinstance(app_id, str) and '.' in app_id:
    bundle_suffix = app_id.split('.', 1)[1]
certs = obj.get('DeveloperCertificates') or []
cert_kind = "UNKNOWN"
if certs and isinstance(certs[0], (bytes, bytearray)):
    cert_kind = classify_cert_kind(certs[0])
has_hid_virtual = 'com.apple.developer.hid.virtual.device' in ent
print(f"==> {os.path.basename(profile)}")
print("  decode_ok: true")
print(f"  bundle_id_suffix: {bundle_suffix}")
print(f"  developer_certificate_kind: {cert_kind}")
print(f"  has_entitlement_hid_virtual_device: {has_hid_virtual}")
PY
  }

  export -f decode_profile
  local profiles
  profiles=$(collect_profiles "$@") || true
  [[ -n "${profiles:-}" ]] || return 0
  while IFS= read -r p; do
    [[ -n "$p" && -f "$p" ]] || continue
    audit_one "$p"
  done <<< "$profiles"
}

cmd_cert_info() {
  local full=0
  if [[ "${1:-}" == "--full" ]]; then
    full=1
    shift
  fi
  [[ $# -eq 1 ]] || die "Usage: ./scripts/ojd signing cert-info [--full] <cert.cer>"
  local cert="$1"
  [[ -f "$cert" ]] || die "Missing file: $cert"
  python3 - "$full" "$cert" <<'PY'
import sys, subprocess
full = int(sys.argv[1]); path = sys.argv[2]
def short(s: str) -> str:
    return s if len(s) <= 12 else (s[:8] + "…" + s[-4:])
serial = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-serial"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip().split("=", 1)[1]
fp = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-fingerprint","-sha1"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip().split("=", 1)[1].replace(":", "").lower()
subj = subprocess.run(["openssl","x509","-inform","DER","-in",path,"-noout","-subject","-nameopt","RFC2253"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip()
ou = subj.split("OU=", 1)[1].split(",", 1)[0] if "OU=" in subj else ""
cn = subj.split("CN=", 1)[1].split(",", 1)[0] if "CN=" in subj else ""
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
}

cmd_profile_info() {
  local full=0
  if [[ "${1:-}" == "--full" ]]; then
    full=1
    shift
  fi
  [[ $# -ge 1 ]] || die "Usage: ./scripts/ojd signing profile-info [--full] <profile1> [profile2...]"
  python3 - "$full" "$@" <<'PY'
import os, sys, plistlib, subprocess, tempfile
full = int(sys.argv[1])
profiles = sys.argv[2:]
def decode_profile(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if (p.returncode == 0 and p.stdout) else b""
def sha1_of_der(der: bytes) -> str:
    out = subprocess.run(["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"], input=der,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout.decode().strip()
    return out.split("=", 1)[1].replace(":", "").lower()
def serial_of_der(der: bytes) -> str:
    out = subprocess.run(["openssl","x509","-inform","DER","-noout","-serial"], input=der,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout.decode().strip()
    return out.split("=", 1)[1]
def subject_rfc2253_of_der(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(der); tmp = f.name
    try:
        return subprocess.run(["openssl","x509","-inform","DER","-in",tmp,"-noout","-subject","-nameopt","RFC2253"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip()
    finally:
        try: os.unlink(tmp)
        except OSError: pass
def short(s: str) -> str:
    return s if len(s) <= 12 else (s[:8] + "…" + s[-4:])
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
    ti = obj.get("TeamIdentifier") or []
    team = ti[0] if isinstance(ti, list) and ti and isinstance(ti[0], str) else "UNKNOWN"
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
    ou = subj.split("OU=", 1)[1].split(",", 1)[0] if "OU=" in subj else ""
    cn = subj.split("CN=", 1)[1].split(",", 1)[0] if "CN=" in subj else ""
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
}

cmd_import_embedded() {
  local profile="${1:-}"
  [[ -n "$profile" ]] || die "Usage: ./scripts/ojd signing import-embedded <profile.provisionprofile>"
  [[ -f "$profile" ]] || die "Missing profile file: $profile"
  local tmp="/tmp/ojd-embedded-devcert.der"
  python3 - "$profile" "$tmp" <<'PY'
import os, sys, plistlib, subprocess
profile = os.path.expanduser(sys.argv[1]); out_path = sys.argv[2]
def decode(path: str) -> bytes:
    p = subprocess.run(["security","cms","-D","-i",path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode == 0 and p.stdout:
        return p.stdout
    p = subprocess.run(["openssl","smime","-inform","der","-verify","-noverify","-in",path],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
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
  echo "Now run:"
  echo "  security find-identity -v -p codesigning"
}

cmd_doctor() {
  # Reuse our own audit/profile-info helpers to keep output safe.
  echo "OpenJoystickDriver signing doctor"
  echo ""
  echo "1) Keychain identities:"
  security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print "  Apple Development SHA1: " tolower($2)} /Developer ID Application:/{print "  Developer ID App SHA1:  " tolower($2)}' || true
  echo ""
  echo "2) Profiles audit:"
  cmd_audit
  echo ""
  echo "Next:"
  echo "  ./scripts/ojd signing configure"
}

case "$cmd" in
  install-profiles) cmd_install_profiles "${1:-}"; exit 0 ;;
  audit) cmd_audit "$@"; exit 0 ;;
  cert-info) cmd_cert_info "$@"; exit 0 ;;
  profile-info) cmd_profile_info "$@"; exit 0 ;;
  import-embedded) cmd_import_embedded "$@"; exit 0 ;;
  doctor) cmd_doctor; exit 0 ;;
  configure) ;; # continue into original implementation
  *) die "Unknown signing command: $cmd" ;;
esac

DEV_ENV="$SCRIPT_DIR/.env.dev"
REL_ENV="$SCRIPT_DIR/.env.release"

GUI_DEV_PROFILE="${GUI_DEV_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver.provisionprofile}"
GUI_DEVID_PROFILE="${GUI_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
DAEMON_DEV_PROFILE="${DAEMON_DEV_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon.provisionprofile}"
DAEMON_DEVID_PROFILE="${DAEMON_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile}"
DEXT_PROFILE="${DEXT_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"
APPLE_DEV_IDENTITY="${APPLE_DEV_IDENTITY:-}"
DEVID_APP_IDENTITY="${DEVID_APP_IDENTITY:-}"

usage() {
  cat <<'TXT'
Usage:
  ./scripts/ojd signing configure

Reads:
  - Keychain code signing identities (Apple Development + Developer ID Application)
  - Provisioning profiles from ~/Library/MobileDevice/Provisioning Profiles/

Writes:
  - scripts/.env.dev
  - scripts/.env.release

Environment overrides (optional):
  GUI_DEV_PROFILE, GUI_DEVID_PROFILE, DAEMON_DEV_PROFILE, DAEMON_DEVID_PROFILE, DEXT_PROFILE
  APPLE_DEV_IDENTITY, DEVID_APP_IDENTITY
TXT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

export PROJECT_DIR
export SCRIPT_DIR
export DEV_ENV
export REL_ENV
export GUI_DEV_PROFILE
export GUI_DEVID_PROFILE
export DAEMON_DEV_PROFILE
export DAEMON_DEVID_PROFILE
export DEXT_PROFILE
export APPLE_DEV_IDENTITY
export DEVID_APP_IDENTITY

python3 - <<'PY'
import os, re, subprocess, plistlib, pathlib, sys

project_dir = pathlib.Path(os.environ.get("PROJECT_DIR", "."))
script_dir = pathlib.Path(os.environ.get("SCRIPT_DIR", "scripts"))

dev_env = pathlib.Path(os.environ.get("DEV_ENV", str(script_dir / ".env.dev")))
rel_env = pathlib.Path(os.environ.get("REL_ENV", str(script_dir / ".env.release")))

gui_dev_profile = os.path.expanduser(os.environ.get("GUI_DEV_PROFILE", ""))
gui_devid_profile = os.path.expanduser(os.environ.get("GUI_DEVID_PROFILE", ""))
daemon_dev_profile = os.path.expanduser(os.environ.get("DAEMON_DEV_PROFILE", ""))
daemon_devid_profile = os.path.expanduser(os.environ.get("DAEMON_DEVID_PROFILE", ""))
dext_profile = os.path.expanduser(os.environ.get("DEXT_PROFILE", ""))

def run(args, *, check=True):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=check)

def must_exist(path: str, label: str):
    if not os.path.isfile(path):
        raise SystemExit(f"ERROR: {label} not found: {path}")

def decode_profile(path: str) -> dict:
    # Prefer Apple tooling when it works, but keep an OpenSSL fallback because
    # `security cms -D` can fail on some machines for `.provisionprofile`.
    p = subprocess.run(
        ["security","cms","-D","-i",path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=False,
    )
    raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        p = subprocess.run(
            ["openssl","smime","-inform","der","-verify","-noverify","-in",path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=False,
        )
        raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        raise SystemExit(
            "ERROR: Could not decode provisioning profile.\n"
            f"  profile: {path}\n"
            "Fix: reinstall/regenerate the profile and re-run `./scripts/ojd signing install-profiles`.\n"
            "Debug (safe): `./scripts/ojd signing audit \"$HOME/Library/MobileDevice/Provisioning Profiles\"/*.provisionprofile`"
        )
    if b"<?xml" in raw:
        raw = raw[raw.index(b"<?xml") :]
    try:
        return plistlib.loads(raw)
    except Exception:
        raise SystemExit(
            "ERROR: Provisioning profile decoded, but plist parsing failed.\n"
            f"  profile: {path}\n"
            "Fix: regenerate the profile in the Developer portal and reinstall it."
        )

def sha1_fingerprint(der_bytes: bytes) -> str:
    p = subprocess.run(
        ["openssl","x509","-inform","DER","-noout","-fingerprint","-sha1"],
        input=der_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    # output: SHA1 Fingerprint=AA:BB:...
    s = p.stdout.decode("utf-8","replace").strip()
    if "=" not in s:
        raise RuntimeError("unexpected openssl fingerprint output")
    return s.split("=",1)[1].replace(":","").lower()

def embedded_cert_sha1_from_profile(path: str) -> str:
    obj = decode_profile(path)
    certs = obj.get("DeveloperCertificates") or []
    if not certs or not isinstance(certs[0], (bytes, bytearray)):
        raise SystemExit(f"ERROR: Could not extract DeveloperCertificates from profile: {path}")
    return sha1_fingerprint(certs[0])

def pick_identity(prefix: str) -> str:
    override = os.environ.get("APPLE_DEV_IDENTITY" if prefix == "Apple Development" else "DEVID_APP_IDENTITY", "")
    if override:
        return override
    out = run(["security","find-identity","-v","-p","codesigning"]).stdout
    matches: list[str] = []
    for line in out.splitlines():
        m = re.search(r'"(' + re.escape(prefix) + r':[^\"]+)"', line)
        if m:
            matches.append(m.group(1))
    if not matches:
        raise SystemExit(f"ERROR: Missing Keychain identity: {prefix} (run `security find-identity -v -p codesigning`)")
    return matches[0]

def team_id_from_profile(path: str) -> str:
    obj = decode_profile(path)
    team_ids = obj.get("TeamIdentifier") or []
    if team_ids and isinstance(team_ids[0], str) and team_ids[0]:
        return team_ids[0]
    ent = obj.get("Entitlements") or {}
    tid = ent.get("com.apple.developer.team-identifier")
    if isinstance(tid, str) and tid:
        return tid
    raise SystemExit(f"ERROR: Could not read TeamIdentifier from profile: {path}")

def profile_name(path: str) -> str:
    obj = decode_profile(path)
    name = obj.get("Name")
    return name if isinstance(name, str) else ""

def profile_has_entitlement(path: str, key: str) -> bool:
    obj = decode_profile(path)
    ent = obj.get("Entitlements") or {}
    return key in ent

must_exist(gui_dev_profile, "GUI dev provisioning profile")
must_exist(gui_devid_profile, "GUI DevID provisioning profile")
must_exist(daemon_dev_profile, "Daemon dev provisioning profile")
must_exist(daemon_devid_profile, "Daemon DevID provisioning profile")
must_exist(dext_profile, "DriverKit dext provisioning profile")

def warn_missing_entitlement(profile_path: str, entitlement: str, label: str, why: str):
    if profile_has_entitlement(profile_path, entitlement):
        return
    print(
        "WARN: Missing entitlement in provisioning profile (feature will be disabled):\n"
        f"  entitlement: {entitlement}\n"
        f"  profile: {profile_path}\n"
        f"  affects: {label}\n"
        f"  why: {why}\n",
        file=sys.stderr,
    )

# NOTE:
# `com.apple.developer.hid.virtual.device` is required ONLY by the process that creates the
# IOHIDUserDevice (user-space virtual gamepad). In this repo that can be:
# - the LaunchAgent daemon (normal path), and/or
# - the GUI app itself when it falls back to the embedded backend.
hid_entitlement = "com.apple.developer.hid.virtual.device"
warn_missing_entitlement(
    daemon_dev_profile,
    hid_entitlement,
    "Daemon dev profile",
    "Compatibility mode (IOHIDUserDevice) will fail if the daemon lacks this entitlement.",
)
warn_missing_entitlement(
    daemon_devid_profile,
    hid_entitlement,
    "Daemon DevID profile",
    "Compatibility mode (IOHIDUserDevice) will fail in release if the daemon lacks this entitlement.",
)
warn_missing_entitlement(
    gui_dev_profile,
    hid_entitlement,
    "GUI dev profile",
    "If the app falls back to the embedded backend, Compatibility mode needs this entitlement in the GUI profile.",
)
warn_missing_entitlement(
    gui_devid_profile,
    hid_entitlement,
    "GUI DevID profile",
    "If the app falls back to the embedded backend, Compatibility mode needs this entitlement in the GUI profile.",
)

dev_team = team_id_from_profile(gui_dev_profile)
rel_team = team_id_from_profile(gui_devid_profile)

# Prefer exact certificate match with provisioning profiles (handles multiple teams/idents cleanly).
def pick_identity_matching_profile(prefix: str, profile_path: str) -> str:
    override = os.environ.get("APPLE_DEV_IDENTITY" if prefix == "Apple Development" else "DEVID_APP_IDENTITY", "")
    if override:
        return override
    want = embedded_cert_sha1_from_profile(profile_path)
    out = run(["security","find-identity","-v","-p","codesigning"]).stdout
    if "0 valid identities found" in out:
        # In some environments `security` cannot read the keychain (sandbox, SSH, locked keychain).
        # We can still proceed by writing the identity as the embedded certificate SHA1.
        #
        # This keeps the scripts non-blocking, while the actual build will still fail
        # if the private key is missing or the keychain is inaccessible.
        print(
            "WARN: macOS reports 0 valid code-signing identities in Keychain.\n"
            "      Proceeding by using the provisioning profile's embedded certificate SHA1.\n"
            "      (The build will still fail if the matching private key isn't available.)\n"
            "Fix checklist (Keychain Access):\n"
            "  1) Unlock the 'login' keychain.\n"
            "  2) Ensure signing certs appear under 'My Certificates' with a private key underneath.\n"
            "  3) If needed, fix keychain permissions then log out/in:\n"
            "       chmod 700 \"$HOME/Library/Keychains\"\n"
            "       chmod 600 \"$HOME/Library/Keychains/login.keychain-db\"\n"
            "  4) Import Apple intermediates (WWDR + DeveloperIDG2CA) if certs show untrusted.\n",
            file=sys.stderr,
        )
        return want
    available_sha1s: list[str] = []
    for line in out.splitlines():
        # Format:  1) <sha1> "<identity>"
        m = re.search(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+\"(' + re.escape(prefix) + r':[^\"]+)\"', line)
        if not m:
            continue
        got = m.group(1).lower()
        available_sha1s.append(got)
        if got == want:
            # Use the SHA1 identity instead of the display name.
            # This avoids confusing cases where the certificate's Subject CN
            # (and thus the Keychain display name) contains a stale/incorrect
            # suffix, while the certificate Subject OU and provisioning profile
            # TeamIdentifier are correct.
            return got
    profile_team = team_id_from_profile(profile_path)
    sha1_str = ", ".join(available_sha1s) if available_sha1s else "UNKNOWN"
    profile_base = os.path.basename(profile_path)
    raise SystemExit(
        f"ERROR: No {prefix} identity matches the certificate embedded in provisioning profile.\n"
        f"  profile: {profile_path}\n"
        f"  profile_team: {profile_team}\n"
        f"  profile_embedded_cert_sha1: {want}\n"
        f"  keychain_{prefix.replace(' ', '_').lower()}_sha1s: {sha1_str}\n"
        "\n"
        "Fix (no guessing):\n"
        f"  1) Show what certificate this profile embeds:\n"
        f"       ./scripts/ojd signing profile-info --full \"$HOME/Library/MobileDevice/Provisioning Profiles/{profile_base}\"\n"
        "  2) Show what identities you can actually sign with (must have private key):\n"
        "       security find-identity -v -p codesigning\n"
        "  3) If the embedded cert SHA1 exists in Keychain but is not a signing identity yet,\n"
        "     import it from the profile (this only helps if you already have the matching private key):\n"
        f"       ./scripts/ojd signing import-embedded \"$HOME/Library/MobileDevice/Provisioning Profiles/{profile_base}\"\n"
        "  4) If you still cannot get a matching identity, regenerate the provisioning profile in the Apple Developer portal\n"
        "     and explicitly select the certificate that matches an identity you have locally.\n"
        "  5) Reinstall profiles: ./scripts/ojd signing install-profiles \"$HOME/Documents/Profiles\"\n"
    )

# Match identities to the certs embedded in the relevant profiles (most reliable).
#
# Important: for building the DriverKit extension we must match the certificate
# embedded in the DEXT provisioning profile (not the GUI provisioning profile).
apple_dev_identity = pick_identity_matching_profile("Apple Development", dext_profile)

dext_build_profile_name = profile_name(dext_profile) or "OpenJoystickDriver (VirtualHIDDevice)"

dev_env.write_text(
    "# Development signing (generated)\n"
    f'CODESIGN_IDENTITY="{apple_dev_identity}"\n'
    f'DEVELOPMENT_TEAM="{dev_team}"\n'
    f'DEXT_BUILD_PROFILE="{dext_build_profile_name}"\n',
    encoding="utf-8",
)

print("Wrote scripts/.env.dev")

try:
    devid_app_identity = pick_identity_matching_profile("Developer ID Application", gui_devid_profile)
except SystemExit as e:
    # Development builds can still proceed. Release signing is publisher-only.
    print("", file=sys.stderr)
    print("WARN: Release signing is NOT configured; Developer ID identity/profile mismatch:", file=sys.stderr)
    print(str(e), file=sys.stderr)
    print("", file=sys.stderr)
    print("Wrote scripts/.env.dev (OK).", file=sys.stderr)
    raise SystemExit(0)

rel_env.write_text(
    "# Release signing (generated). Add notarization credentials separately.\n"
    f'CODESIGN_IDENTITY="{devid_app_identity}"\n'
    f'DEVELOPMENT_TEAM="{rel_team}"\n'
    f'DEXT_BUILD_IDENTITY="{apple_dev_identity}"\n'
    f'DEXT_BUILD_PROFILE="{dext_build_profile_name}"\n'
    f'GUI_PROVISIONING_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/{pathlib.Path(gui_devid_profile).name}"\n'
    f'DAEMON_PROVISIONING_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/{pathlib.Path(daemon_devid_profile).name}"\n',
    encoding="utf-8",
)

print("Wrote scripts/.env.release")
PY
