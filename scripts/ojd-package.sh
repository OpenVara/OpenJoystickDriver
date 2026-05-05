#!/usr/bin/env bash
# Release packaging helper for notarized tester builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

die() { echo "ERROR: $*" >&2; exit 2; }

usage() {
  cat <<'TXT'
Usage:
  OJD_ENV=release ./scripts/ojd package tester [version]

Builds a release-signed app, embeds the DriverKit extension, submits it for
notarization, staples the accepted ticket, and writes:

  .build/release-artifacts/OpenJoystickDriver-<version>-macOS.zip

This does not install the app, register the LaunchAgent, or submit a sysext
activation request on the build machine.
TXT
}

cmd="${1:-}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  usage
  exit 0
fi

[[ "$cmd" == "tester" ]] || die "Unknown package command: ${cmd:-<empty>} (expected: tester)"
[[ "$OJD_ENV" == "release" ]] || die "package tester requires OJD_ENV=release"

version="${1:-${GITHUB_REF_NAME:-$(date -u +%Y%m%d%H%M%S)}}"
safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
artifact_dir="$PROJECT_DIR/.build/release-artifacts"
app_path="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app"
notary_zip="$PROJECT_DIR/.build/OpenJoystickDriver-notarize.zip"
artifact_zip="$artifact_dir/OpenJoystickDriver-${safe_version}-macOS.zip"

mkdir -p "$artifact_dir"

echo "=== Build release app bundle ==="
OJD_ENV=release /usr/bin/env bash "$SCRIPT_DIR/ojd-build.sh" build release

echo ""
echo "=== Build and embed DriverKit extension ==="
OJD_ENV=release OJD_SKIP_INSTALL=1 /usr/bin/env bash "$SCRIPT_DIR/ojd-build.sh" build dext

[[ -d "$app_path" ]] || die "App bundle not found: $app_path"

echo ""
echo "=== Verify signed app before notarization ==="
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo ""
echo "=== Notarize and staple ==="
OJD_ENV=release \
  OJD_NOTARIZE_APP="$app_path" \
  OJD_NOTARIZE_ZIP="$notary_zip" \
  /usr/bin/env bash "$SCRIPT_DIR/ojd-notarize.sh" submit

echo ""
echo "=== Verify notarized app ==="
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"

echo ""
echo "=== Create tester zip ==="
/usr/bin/ditto -c -k --keepParent "$app_path" "$artifact_zip"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo ""
echo "Tester artifact ready:"
echo "  $artifact_zip"
