#!/usr/bin/env bash
# Run SwiftLint on all tracked Swift source files.
#
# USAGE:
#   ./scripts/lint.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"
swiftlint lint --strict
