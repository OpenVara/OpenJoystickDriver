#!/usr/bin/env bash
# Update OpenJoystickDriver release version references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/bump-version.sh <version>
  ./scripts/ojd bump-version <version>

Examples:
  ./scripts/ojd bump-version 0.1.0-rc.2
  ./scripts/ojd bump-version 0.1.0

Updates:
  - Sources/OpenJoystickDriver/CLI.swift
  - scripts/README.md release examples

The target version must already have a CHANGELOG.md heading.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

version="${1:-}"
if [[ "$version" == "" || "$version" == "-h" || "$version" == "--help" || "$version" == "help" ]]; then
  usage
  exit 0
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  die "Version must be SemVer, for example 0.1.0-rc.2"
fi

cli_file="$PROJECT_DIR/Sources/OpenJoystickDriver/CLI.swift"
scripts_readme="$PROJECT_DIR/scripts/README.md"
changelog="$PROJECT_DIR/CHANGELOG.md"

[[ -f "$cli_file" ]] || die "Missing $cli_file"
[[ -f "$scripts_readme" ]] || die "Missing $scripts_readme"
[[ -f "$changelog" ]] || die "Missing $changelog"

if ! grep -Eq "^## ${version//./\\.}($|[[:space:]])" "$changelog"; then
  die "CHANGELOG.md must contain heading: ## $version"
fi

python3 - "$version" "$cli_file" "$scripts_readme" <<'PY'
import re
import sys
from pathlib import Path

version, cli_path, readme_path = sys.argv[1:]

replacements = [
    (
        Path(cli_path),
        [
            (
                re.compile(
                    r"OpenJoystickDriver v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"OpenJoystickDriver v{version}",
            ),
        ],
    ),
    (
        Path(readme_path),
        [
            (
                re.compile(
                    r"\./scripts/ojd package release \d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"./scripts/ojd package release {version}",
            ),
            (
                re.compile(
                    r"`\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?` and by manual dispatch"
                ),
                f"`{version}` and by manual dispatch",
            ),
        ],
    ),
]

changed = []
for path, patterns in replacements:
    text = path.read_text()
    updated = text
    for pattern, repl in patterns:
        updated = pattern.sub(repl, updated)
    if updated != text:
        path.write_text(updated)
        changed.append(str(path))

for path in changed:
    print(f"updated {path}")
if not changed:
    print("version references already up to date")
PY

echo "Version set to $version"
