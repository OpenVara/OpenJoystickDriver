#!/usr/bin/env bash
# Notarize the app bundle with Apple. Requires OJD_ENV=release.
#
# Prerequisites:
#   1. Developer ID signing (scripts/.env.release)
#   2. NOTARIZE_APPLE_ID and NOTARIZE_PASSWORD set in scripts/.env.release
#
# Environment variables:
#   NOTARIZE_TIMEOUT_MINUTES  — overall timeout (default: 180, i.e. 3 hours)
#                               First-ever submissions can take hours; subsequent ones ~5 min.
#   NOTARIZE_POLL_INTERVAL    — seconds between polls (default: 30)
#   NOTARIZE_MAX_RETRIES      — consecutive transient failures before abort (default: 5)
#
# USAGE:
#   OJD_ENV=release ./scripts/notarize.sh
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ "$OJD_ENV" != "release" ]]; then
  echo "ERROR: Notarization requires OJD_ENV=release"
  exit 1
fi

if [[ -z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_PASSWORD:-}" ]]; then
  echo "ERROR: Notarization credentials not set in scripts/.env.release"
  echo ""
  echo "  NOTARIZE_APPLE_ID  = your Apple ID email"
  echo "  NOTARIZE_PASSWORD  = app-specific password from:"
  echo "    appleid.apple.com → Sign-In and Security → App-Specific Passwords"
  exit 1
fi

APP="/Applications/OpenJoystickDriver.app"
ZIP_PATH="$PROJECT_DIR/.build/OpenJoystickDriver-notarize.zip"

TIMEOUT_MINUTES="${NOTARIZE_TIMEOUT_MINUTES:-180}"
POLL_INTERVAL="${NOTARIZE_POLL_INTERVAL:-30}"
MAX_RETRIES="${NOTARIZE_MAX_RETRIES:-5}"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: App not found at $APP"
  echo "Run OJD_ENV=release ./scripts/rebuild.sh first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Create zip for upload
# ---------------------------------------------------------------------------
echo "Creating zip for notarization..."
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
echo "  Zip: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# ---------------------------------------------------------------------------
# Step 2a: Submit to Apple (no --wait)
# ---------------------------------------------------------------------------
echo "Submitting to Apple for notarization..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$NOTARIZE_APPLE_ID" \
  --password "$NOTARIZE_PASSWORD" \
  --team-id "$DEVELOPMENT_TEAM" 2>&1)

echo "$SUBMIT_OUTPUT"

# Parse submission ID (UUID) from output
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "ERROR: Failed to parse submission ID from notarytool output"
  exit 1
fi

echo "  Submission ID: $SUBMISSION_ID"

# Remove zip now — it's already uploaded
rm -f "$ZIP_PATH"

# ---------------------------------------------------------------------------
# Step 2b: Poll for completion with timeout and retry
# ---------------------------------------------------------------------------
DEADLINE=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))
CONSECUTIVE_FAILURES=0

echo "Polling for notarization status (timeout: ${TIMEOUT_MINUTES}m, interval: ${POLL_INTERVAL}s)..."
echo "  Note: First-ever submissions can take hours (Apple may also delay on weekends)."
echo "        Subsequent ones typically finish in ~5 min."
echo ""

while true; do
  NOW=$(date +%s)
  if (( NOW >= DEADLINE )); then
    echo "ERROR: Notarization timed out after ${TIMEOUT_MINUTES} minutes"
    echo "  Submission ID: $SUBMISSION_ID"
    echo ""
    echo "  The submission is still queued with Apple — it may yet complete."
    echo "  Check status:  OJD_ENV=release ./scripts/notarize-status.sh $SUBMISSION_ID"
    echo "  View history:  OJD_ENV=release ./scripts/notarize-status.sh"
    echo ""
    echo "  If it completes later, staple manually:"
    echo "    xcrun stapler staple $APP"
    exit 1
  fi

  REMAINING=$(( (DEADLINE - NOW) / 60 ))

  # Query status, handling transient failures
  if INFO_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --password "$NOTARIZE_PASSWORD" \
    --team-id "$DEVELOPMENT_TEAM" 2>&1); then
    CONSECUTIVE_FAILURES=0
  else
    CONSECUTIVE_FAILURES=$(( CONSECUTIVE_FAILURES + 1 ))
    echo "[$(date '+%H:%M:%S')] Poll failed (attempt $CONSECUTIVE_FAILURES/$MAX_RETRIES): $(echo "$INFO_OUTPUT" | head -1)"
    if (( CONSECUTIVE_FAILURES >= MAX_RETRIES )); then
      echo "ERROR: $MAX_RETRIES consecutive poll failures — giving up"
      echo "$INFO_OUTPUT"
      exit 1
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  STATUS=$(echo "$INFO_OUTPUT" | grep -i "status:" | head -1 | sed 's/.*status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | xargs)

  echo "[$(date '+%H:%M:%S')] Status: $STATUS (${REMAINING}m remaining)"

  case "$STATUS" in
    accepted)
      echo ""
      echo "Notarization accepted."
      break
      ;;
    invalid|rejected)
      echo ""
      echo "ERROR: Notarization failed with status: $STATUS"
      echo ""
      echo "Fetching notarization log..."
      xcrun notarytool log "$SUBMISSION_ID" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --password "$NOTARIZE_PASSWORD" \
        --team-id "$DEVELOPMENT_TEAM" 2>&1 || true
      exit 1
      ;;
    "in progress"|*)
      sleep "$POLL_INTERVAL"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Step 3: Staple the ticket to the app
# ---------------------------------------------------------------------------
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

echo ""
echo "Notarization complete."
echo "  App: $APP"
echo "  Verify: spctl --assess --verbose=4 $APP"
