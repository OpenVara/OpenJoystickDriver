#!/usr/bin/env bash
# Check notarization status or history using credentials from .env.release.
#
# USAGE:
#   ./scripts/notarize-status.sh <submission-id>   # check specific submission
#   ./scripts/notarize-status.sh                    # show recent history
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ "$OJD_ENV" != "release" ]]; then
  echo "ERROR: Requires OJD_ENV=release"
  exit 1
fi

if [[ -z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_PASSWORD:-}" ]]; then
  echo "ERROR: NOTARIZE_APPLE_ID and NOTARIZE_PASSWORD must be set in scripts/.env.release"
  exit 1
fi

AUTH_ARGS=(
  --apple-id "$NOTARIZE_APPLE_ID"
  --password "$NOTARIZE_PASSWORD"
  --team-id "$DEVELOPMENT_TEAM"
)

if [[ "${1:-}" == "--log" && -n "${2:-}" ]]; then
  echo "Fetching log for: $2"
  xcrun notarytool log "$2" "${AUTH_ARGS[@]}"
elif [[ -n "${1:-}" ]]; then
  echo "Checking submission: $1"
  xcrun notarytool info "$1" "${AUTH_ARGS[@]}"

  echo ""
  echo "To fetch the log:  OJD_ENV=release $0 --log $1"
else
  echo "Recent notarization history:"
  xcrun notarytool history "${AUTH_ARGS[@]}"
fi
