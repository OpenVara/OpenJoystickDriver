#!/usr/bin/env bash
# Fast development loop: build, sign, and run daemon.
#
# Signs with CODESIGN_IDENTITY if set, otherwise ad-hoc.
# With real Apple Development cert, no sudo needed for USB access.
#
# USAGE:
#   ./scripts/dev.sh
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./scripts/dev.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

ENTITLEMENTS="Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements"
IDENTITY="${CODESIGN_IDENTITY:--}"
DAEMON=".build/debug/OpenJoystickDriverDaemon"

swift build --product OpenJoystickDriverDaemon

codesign --sign "$IDENTITY" --force \
  --entitlements "$ENTITLEMENTS" \
  "$DAEMON"

echo "Running daemon (Ctrl+C to stop)..."
if [[ "$IDENTITY" == "-" ]]; then
  sudo "$DAEMON"
else
  "$DAEMON"
fi
