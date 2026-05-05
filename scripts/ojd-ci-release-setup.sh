#!/usr/bin/env bash
# Import release signing material from GitHub Actions secrets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

die() { echo "ERROR: $*" >&2; exit 2; }

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required environment variable: $name"
}

write_base64_file() {
  local name="$1" out="$2"
  require_var "$name"
  printf '%s' "${!name}" | base64 --decode > "$out"
}

require_var APPLE_DEVELOPMENT_CERT_BASE64
require_var DEVELOPER_ID_APPLICATION_CERT_BASE64
require_var CERTIFICATE_SECRET
require_var KEYCHAIN_SECRET
require_var RUNNER_TEMP
require_var OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64
require_var OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64
require_var OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64

keychain_path="$RUNNER_TEMP/openjoystickdriver-release.keychain-db"
profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
payload_dir="$RUNNER_TEMP/openjoystickdriver-release-payloads"

mkdir -p "$profiles_dir" "$payload_dir"

echo "Creating temporary signing keychain..."
security create-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"

apple_dev_payload="$payload_dir/apple-development-cert.blob"
developer_id_payload="$payload_dir/developer-id-application-cert.blob"
write_base64_file APPLE_DEVELOPMENT_CERT_BASE64 "$apple_dev_payload"
write_base64_file DEVELOPER_ID_APPLICATION_CERT_BASE64 "$developer_id_payload"

echo "Importing signing certificates..."
security import "$apple_dev_payload" -k "$keychain_path" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
security import "$developer_id_payload" -k "$keychain_path" -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$keychain_path"

echo "Installing provisioning profiles..."
write_base64_file OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_DevID.provisionprofile"
write_base64_file OPENJOYSTICKDRIVER_DAEMON_DEVID_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriverDaemon_DevID.provisionprofile"
write_base64_file OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64 "$profiles_dir/OpenJoystickDriver_VirtualHIDDevice.provisionprofile"

echo "Generating release signing environment..."
(
  cd "$PROJECT_DIR"
  ./scripts/ojd signing configure
)

echo "Release signing setup complete."
echo "Safe identity summary:"
security find-identity -v -p codesigning "$keychain_path" | awk '/Apple Development:|Developer ID Application:/ {print "  " $2}'
