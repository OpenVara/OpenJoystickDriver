#!/usr/bin/env bash
# Audit provisioning profiles without printing sensitive identifiers.
#
# Prints:
#   - profile filename
#   - bundle id suffix (e.g. com.openjoystickdriver.VirtualHIDDevice)
#   - developer certificate kind (Apple Development vs Developer ID Application)
#   - whether com.apple.developer.hid.virtual.device is present
#
# Exit codes:
#   0: OK
set -euo pipefail

decode_profile() {
  local profile="$1"
  # `security cms -D` is preferred but can fail on some systems; OpenSSL fallback.
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
    p = subprocess.run(
        ['bash','-lc', f'decode_profile {path!r}'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    if p.returncode != 0 or not p.stdout:
        raise RuntimeError("decode failed")
    return p.stdout

def classify_cert_kind(der: bytes) -> str:
    with tempfile.NamedTemporaryFile(prefix='ojd_cert_', suffix='.der', delete=True) as tf:
        tf.write(der)
        tf.flush()
        p = subprocess.run(
            ['openssl','x509','-inform','DER','-in',tf.name,'-noout','-subject'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
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

# Print only non-sensitive fields (no Team ID / application identifier prefixes).
print(f"==> {os.path.basename(profile)}")
print("  decode_ok: true")
print(f"  bundle_id_suffix: {bundle_suffix}")
print(f"  developer_certificate_kind: {cert_kind}")
print(f"  has_entitlement_hid_virtual_device: {has_hid_virtual}")
PY
}

main() {
  local rc=0
  local profiles
  profiles=$(collect_profiles "$@")
  if [[ -z "${profiles:-}" ]]; then
    return 0
  fi

  # Export function for the Python subprocess wrapper.
  export -f decode_profile

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ ! -f "$p" ]]; then
      continue
    fi
    audit_one "$p"
    status=$?
    if [[ "$status" -ne 0 ]]; then
      # Preserve the strongest signal (missing new entitlement).
      if [[ "$rc" -ne 2 ]]; then
        rc="$status"
      fi
    fi
  done <<< "$profiles"
  return "$rc"
}

main "$@"
