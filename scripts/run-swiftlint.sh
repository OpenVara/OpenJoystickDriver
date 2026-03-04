#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$SCRIPT_DIR/swiftlint-results_${TIMESTAMP}.txt"

cd "$REPO_ROOT"
rm -f "$SCRIPT_DIR"/swiftlint-results_*.txt

git ls-files --cached --others --exclude-standard --full-name -- '*.swift' | while read -r file; do
    swiftlint lint "$file"
done | tee "$REPORT_FILE"
