#!/usr/bin/env bash
# Prepare GitHub Actions release secrets from local signing assets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

die() { echo "ERROR: $*" >&2; exit 2; }

usage() {
  cat <<'TXT'
Usage:
  ./scripts/ojd signing export-github-secrets [options]

Options:
  --apply                              Run gh secret set after writing files
  --repo owner/name                     Repository for gh secret set
  --out <dir>                          Output directory
  --apple-development-identity <path>   Apple Development identity export
  --developer-id-identity <path>        Developer ID Application identity export

Environment overrides:
  APPLE_DEVELOPMENT_IDENTITY_EXPORT
  DEVELOPER_ID_APPLICATION_IDENTITY_EXPORT
  CERTIFICATE_SECRET
  KEYCHAIN_SECRET
  NOTARIZE_APPLE_ID
  NOTARIZE_PASSWORD

If identity export paths are omitted, the script exports signing identities from
your login keychain into the private output directory. Keychain may prompt for
permission. The script writes one private file per secret and an
apply-github-secrets.sh helper that imports them with GitHub CLI without
printing secret values.
TXT
}

repo_arg=()
apply=0
out_dir="$PROJECT_DIR/.build/github-actions-secrets"
apple_development_identity="${APPLE_DEVELOPMENT_IDENTITY_EXPORT:-}"
developer_id_identity="${DEVELOPER_ID_APPLICATION_IDENTITY_EXPORT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
    --apply)
      apply=1
      shift
      ;;
    --repo)
      [[ -n "${2:-}" ]] || die "Missing value for --repo"
      repo_arg=(--repo "$2")
      shift 2
      ;;
    --out)
      [[ -n "${2:-}" ]] || die "Missing value for --out"
      out_dir="$2"
      shift 2
      ;;
    --apple-development-identity)
      [[ -n "${2:-}" ]] || die "Missing value for --apple-development-identity"
      apple_development_identity="$2"
      shift 2
      ;;
    --developer-id-identity)
      [[ -n "${2:-}" ]] || die "Missing value for --developer-id-identity"
      developer_id_identity="$2"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

read_secret() {
  local var="$1" prompt="$2"
  if [[ -n "${!var:-}" ]]; then
    printf '%s' "${!var}"
    return 0
  fi
  local value
  printf '%s: ' "$prompt" >&2
  IFS= read -r -s value
  printf '\n' >&2
  [[ -n "$value" ]] || die "$var cannot be empty"
  printf '%s' "$value"
}

base64_file() {
  local path="$1"
  python3 - "$path" <<'PY'
import base64, pathlib, sys
path = pathlib.Path(sys.argv[1]).expanduser()
sys.stdout.write(base64.b64encode(path.read_bytes()).decode("ascii"))
PY
}

write_secret_file() {
  local name="$1" value="$2"
  printf '%s' "$value" > "$values_dir/$name.txt"
}

gui_devid_profile="${OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_DevID.provisionprofile}"
daemon_devid_profile="${OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriverDaemon_DevID.provisionprofile}"
dext_profile="${OPENJOYSTICKDRIVER_DEXT_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/OpenJoystickDriver_VirtualHIDDevice.provisionprofile}"

[[ -f "$gui_devid_profile" ]] || die "Missing GUI Developer ID profile: $gui_devid_profile"
[[ -f "$daemon_devid_profile" ]] || die "Missing daemon Developer ID profile: $daemon_devid_profile"
[[ -f "$dext_profile" ]] || die "Missing DriverKit profile: $dext_profile"

certificate_secret="$(read_secret CERTIFICATE_SECRET 'identity export password')"
notarize_apple_id="$(read_secret NOTARIZE_APPLE_ID 'Apple ID email for notarization')"
notarize_password="$(read_secret NOTARIZE_PASSWORD 'Apple app-specific password for notarization')"
keychain_secret="${KEYCHAIN_SECRET:-$(openssl rand -base64 32 | tr -d '\n')}"

values_dir="$out_dir/values"
mkdir -p "$values_dir"
chmod 700 "$out_dir" "$values_dir"

if [[ -z "$apple_development_identity" || -z "$developer_id_identity" ]]; then
  auto_identity="$out_dir/signing-identities-export"
  echo "No identity export paths supplied; exporting signing identities from login keychain."
  echo "Keychain may prompt for permission."
  security export \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -t identities \
    -f pkcs12 \
    -P "$certificate_secret" \
    -o "$auto_identity" >/dev/null
  chmod 600 "$auto_identity"
  apple_development_identity="${apple_development_identity:-$auto_identity}"
  developer_id_identity="${developer_id_identity:-$auto_identity}"
fi

[[ -f "$apple_development_identity" ]] || die "Missing Apple Development identity export: $apple_development_identity"
[[ -f "$developer_id_identity" ]] || die "Missing Developer ID Application identity export: $developer_id_identity"

write_secret_file APPLE_DEVELOPMENT_CERT_BASE64 "$(base64_file "$apple_development_identity")"
write_secret_file DEVELOPER_ID_APPLICATION_CERT_BASE64 "$(base64_file "$developer_id_identity")"
write_secret_file CERTIFICATE_SECRET "$certificate_secret"
write_secret_file KEYCHAIN_SECRET "$keychain_secret"
write_secret_file OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 "$(base64_file "$gui_devid_profile")"
write_secret_file OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64 "$(base64_file "$daemon_devid_profile")"
write_secret_file OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64 "$(base64_file "$dext_profile")"
write_secret_file NOTARIZE_APPLE_ID "$notarize_apple_id"
write_secret_file NOTARIZE_PASSWORD "$notarize_password"
chmod 600 "$values_dir"/*.txt

cat > "$out_dir/apply-github-secrets.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_args=()
if [[ "${1:-}" == "--repo" ]]; then
  [[ -n "${2:-}" ]] || { echo "ERROR: Missing value for --repo" >&2; exit 2; }
  repo_args=(--repo "$2")
  shift 2
fi

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI not found" >&2; exit 2; }

for file in "$SCRIPT_DIR"/values/*.txt; do
  name="$(basename "$file" .txt)"
  echo "Setting $name"
  gh secret set "$name" "${repo_args[@]}" < "$file"
done
SH
chmod 700 "$out_dir/apply-github-secrets.sh"

cat > "$out_dir/README.txt" <<TXT
OpenJoystickDriver GitHub Actions secrets

Files:
  values/*.txt                 One secret value per file
  apply-github-secrets.sh      Imports values with gh secret set

Keep this directory private. Delete it after importing secrets if you do not
need a local backup.
TXT
chmod 600 "$out_dir/README.txt"

echo "Wrote GitHub Actions secret files:"
echo "  $out_dir"
echo ""
echo "Import with:"
if [[ "${#repo_arg[@]}" -gt 0 ]]; then
  echo "  $out_dir/apply-github-secrets.sh --repo ${repo_arg[1]}"
else
  echo "  $out_dir/apply-github-secrets.sh"
fi

if [[ "$apply" -eq 1 ]]; then
  "$out_dir/apply-github-secrets.sh" "${repo_arg[@]}"
fi
