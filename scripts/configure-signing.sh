#!/usr/bin/env bash
# Generate scripts/.env.dev and scripts/.env.release from Keychain + installed provisioning profiles.
#
# Goals:
# - No manual copy/paste of identities or Team IDs
# - Avoid heredoc pitfalls when pasting into wrapped terminals
# - Keep output non-sensitive (does not print identity strings)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

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
  ./scripts/configure-signing.sh

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
            "Fix: reinstall/regenerate the profile and re-run `./scripts/install-profiles.sh`.\n"
            "Debug (safe): `./scripts/profile-audit.sh \"$HOME/Library/MobileDevice/Provisioning Profiles\"/*.provisionprofile`"
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
    raise SystemExit(
        f"ERROR: No {prefix} identity matches the certificate embedded in provisioning profile.\n"
        f"  profile: {profile_path}\n"
        f"  profile_team: {profile_team}\n"
        f"  profile_embedded_cert_sha1: {want}\n"
        f"  keychain_{prefix.replace(' ', '_').lower()}_sha1s: {sha1_str}\n"
        "\n"
        "Fix (no guessing):\n"
        "  1) Identify the Apple Development cert you have locally:\n"
        "       ./scripts/cert-info.sh --full \"$HOME/Documents/Certificates/development.cer\"\n"
        "  2) Identify which cert your DEXT profile embeds:\n"
        "       ./scripts/profile-cert-info.sh --full \"$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile\"\n"
        "  3) In Apple Developer portal, regenerate the DEXT provisioning profile and explicitly select\n"
        "     the Apple Development certificate that matches your local cert.\n"
        "     (If the portal picked a different cert, the embedded SHA1 will differ and builds will fail.)\n"
        "  4) Reinstall profiles: ./scripts/install-profiles.sh \"$HOME/Documents/Profiles\"\n"
    )

# Match identities to the certs embedded in the relevant profiles (most reliable).
#
# Important: for building the DriverKit extension we must match the certificate
# embedded in the DEXT provisioning profile (not the GUI provisioning profile).
apple_dev_identity = pick_identity_matching_profile("Apple Development", dext_profile)
devid_app_identity = pick_identity_matching_profile("Developer ID Application", gui_devid_profile)

dext_build_profile_name = profile_name(dext_profile) or "OpenJoystickDriver (VirtualHIDDevice)"

dev_env.write_text(
    "# Development signing (generated)\n"
    f'CODESIGN_IDENTITY="{apple_dev_identity}"\n'
    f'DEVELOPMENT_TEAM="{dev_team}"\n'
    f'DEXT_BUILD_PROFILE="{dext_build_profile_name}"\n',
    encoding="utf-8",
)

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

print("Wrote scripts/.env.dev")
print("Wrote scripts/.env.release")
PY
