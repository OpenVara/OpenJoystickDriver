#!/usr/bin/env bash
# Build, sign, and immediately run daemon (fast development loop).
#
# Signs with CODESIGN_IDENTITY if set, otherwise ad-hoc (-).
# With real Apple Development cert no sudo is required for USB access.
#
# USAGE:
#   ./scripts/run-dev.sh
#   CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/run-dev.sh
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "Building daemon..."
cd "$PROJECT_DIR"
swift build --product OpenJoystickDriverDaemon

echo "Signing daemon using: $IDENTITY"
ojd_sign "$DAEMON_DEBUG" --entitlements "$ENTITLEMENTS"

echo "Running daemon (Ctrl+C to stop)..."
if [[ "$IDENTITY" == "-" ]]; then
  sudo "$DAEMON_DEBUG"
else
  "$DAEMON_DEBUG"
fi
