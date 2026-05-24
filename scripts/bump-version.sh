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
  - Sources/OpenJoystickDriver/App/AppModel.swift fallback version
  - scripts/README.md release examples
  - scripts/ojd-build.sh generated GUI/daemon bundle versions
  - DriverKitExtension/Info.plist short version

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
app_model_file="$PROJECT_DIR/Sources/OpenJoystickDriver/App/AppModel.swift"
scripts_readme="$PROJECT_DIR/scripts/README.md"
build_script="$PROJECT_DIR/scripts/ojd-build.sh"
dext_plist="$PROJECT_DIR/DriverKitExtension/Info.plist"
changelog="$PROJECT_DIR/CHANGELOG.md"

[[ -f "$cli_file" ]] || die "Missing $cli_file"
[[ -f "$app_model_file" ]] || die "Missing $app_model_file"
[[ -f "$scripts_readme" ]] || die "Missing $scripts_readme"
[[ -f "$build_script" ]] || die "Missing $build_script"
[[ -f "$dext_plist" ]] || die "Missing $dext_plist"
[[ -f "$changelog" ]] || die "Missing $changelog"

if ! grep -Fxq "## $version" "$changelog"; then
  die "CHANGELOG.md must contain heading: ## $version"
fi

python3 - "$version" "$cli_file" "$app_model_file" "$scripts_readme" "$build_script" "$dext_plist" <<'PY'
import re
import sys
from pathlib import Path

version, cli_path, app_model_path, readme_path, build_script_path, dext_plist_path = sys.argv[1:]

replacements = [
    (
        Path(cli_path),
        [
            (
                "CLI version strings",
                re.compile(
                    r"OpenJoystickDriver v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"OpenJoystickDriver v{version}",
                2,
            ),
        ],
    ),
    (
        Path(app_model_path),
        [
            (
                "AppModel fallback version",
                re.compile(
                    r'(Bundle\.main\.infoDictionary\?\["CFBundleShortVersionString"\] as\? String \?\? ")\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(")'
                ),
                rf"\g<1>{version}\g<2>",
                1,
            ),
        ],
    ),
    (
        Path(readme_path),
        [
            (
                "scripts README package release example",
                re.compile(
                    r"\./scripts/ojd package release \d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
                ),
                f"./scripts/ojd package release {version}",
                1,
            ),
            (
                "scripts README manual dispatch version example",
                re.compile(
                    r"`\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?` and by manual dispatch"
                ),
                f"`{version}` and by manual dispatch",
                1,
            ),
        ],
    ),
    (
        Path(build_script_path),
        [
            (
                "ojd-build GUI/daemon short versions",
                re.compile(
                    r"(<key>CFBundleShortVersionString</key>\n[ \t]*<string>)\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(</string>)"
                ),
                rf"\g<1>{version}\g<2>",
                2,
            ),
        ],
    ),
    (
        Path(dext_plist_path),
        [
            (
                "DriverKit short version",
                re.compile(
                    r"(<key>CFBundleShortVersionString</key>\n[ \t]*<string>)\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(</string>)"
                ),
                rf"\g<1>{version}\g<2>",
                1,
            ),
        ],
    ),
]

missing = []
updates = []
for path, patterns in replacements:
    text = path.read_text()
    updated = text
    file_missing = False
    for description, pattern, repl, minimum in patterns:
        updated, count = pattern.subn(repl, updated)
        if count < minimum:
            missing.append(f"{path}: {description} (expected at least {minimum}, found {count})")
            file_missing = True
    if not file_missing and updated != text:
        updates.append((path, updated))

if missing:
    for item in missing:
        print(f"missing expected version reference: {item}", file=sys.stderr)
    sys.exit(1)

changed = []
for path, updated in updates:
    path.write_text(updated)
    changed.append(str(path))

for path in changed:
    print(f"updated {path}")
if not changed:
    print("version references already up to date")
PY

echo "Version set to $version"
