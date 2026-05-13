#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTERS_FILE="$PROJECT_DIR/.rtk/filters.toml"

usage() {
  cat <<'USAGE'
OpenJoystickDriver RTK filters

Usage:
  ./scripts/ojd rtk install-filters

Creates or appends project-local RTK filters in .rtk/filters.toml.
Existing filter names are skipped, so repeated runs do not duplicate entries.
USAGE
}

ensure_filters_file() {
  mkdir -p "$(dirname "$FILTERS_FILE")"
  if [[ ! -f "$FILTERS_FILE" ]]; then
    printf 'schema_version = 1\n' >"$FILTERS_FILE"
  elif ! grep -Eq '^schema_version[[:space:]]*=' "$FILTERS_FILE"; then
    tmp="$(mktemp)"
    printf 'schema_version = 1\n\n' >"$tmp"
    cat "$FILTERS_FILE" >>"$tmp"
    mv "$tmp" "$FILTERS_FILE"
  fi
}

append_filter() {
  local name="$1"
  local body="$2"
  if grep -Fqx "[filters.$name]" "$FILTERS_FILE"; then
    echo "skip $name"
    return
  fi
  printf '\n%s\n' "$body" >>"$FILTERS_FILE"
  echo "add  $name"
}

COMMON_SWIFT_TEST=$(cat <<'FILTER'
[filters.common-swift-test]
description = "Compact Swift test output"
match_command = "^swift\\s+test\\b"
strip_ansi = true
match_output = [{ pattern = "Test Suite '.+' passed", message = "ok (swift tests passed)", unless = "(?i)error|fail|failed|fatal|warning" }]
keep_lines_matching = ["(?i)error|fail|failed|fatal|warning|unexpected|issue recorded", "^Test Suite '.+' (failed|passed)", "^Test Case '.+' failed"]
truncate_lines_at = 220
max_lines = 120
filter_stderr = true
on_empty = "ok (swift test produced no notable lines)"

[[tests.common-swift-test]]
name = "successful swift test compacts"
input = "Building for debugging...\n[1/3] Compiling Package Foo.swift\nTest Suite 'All tests' started at 2026-05-13.\nTest Case 'DeviceTests.testFoo' started.\nTest Case 'DeviceTests.testFoo' passed (0.001 seconds).\nTest Suite 'All tests' passed at 2026-05-13."
expected = "ok (swift tests passed)"

[[tests.common-swift-test]]
name = "swift test failure is preserved"
input = "Test Suite 'All tests' started at 2026-05-13.\nTest Case 'DeviceTests.testFoo' failed (0.001 seconds).\n/repo/Tests/DeviceTests.swift:10: error: DeviceTests.testFoo : XCTAssertEqual failed\nTest Suite 'All tests' failed at 2026-05-13."
expected = "Test Case 'DeviceTests.testFoo' failed (0.001 seconds).\n/repo/Tests/DeviceTests.swift:10: error: DeviceTests.testFoo : XCTAssertEqual failed\nTest Suite 'All tests' failed at 2026-05-13."
FILTER
)

COMMON_XCODEBUILD=$(cat <<'FILTER'
[filters.common-xcodebuild]
description = "Compact xcodebuild output"
match_command = "^xcodebuild\\b"
strip_ansi = true
match_output = [
  { pattern = "\\*\\* BUILD SUCCEEDED \\*\\*", message = "ok (xcodebuild succeeded)", unless = "(?i)error|fail|failed|warning" },
  { pattern = "\\*\\* TEST SUCCEEDED \\*\\*", message = "ok (xcodebuild tests succeeded)", unless = "(?i)error|fail|failed|warning" },
]
keep_lines_matching = ["(?i)error:|warning:|fatal error|failed|testing failed|build failed", "\\*\\* (BUILD|TEST) (FAILED|SUCCEEDED) \\*\\*"]
truncate_lines_at = 240
max_lines = 120
filter_stderr = true
on_empty = "ok (xcodebuild produced no notable lines)"

[[tests.common-xcodebuild]]
name = "successful xcodebuild compacts"
input = "CompileSwift normal arm64 Foo.swift\nCodeSign /tmp/App.app\n** BUILD SUCCEEDED **"
expected = "ok (xcodebuild succeeded)"

[[tests.common-xcodebuild]]
name = "xcodebuild error is preserved"
input = "CompileSwift normal arm64 Foo.swift\n/repo/Sources/Foo.swift:5:10: error: cannot find 'bar' in scope\n** BUILD FAILED **"
expected = "/repo/Sources/Foo.swift:5:10: error: cannot find 'bar' in scope\n** BUILD FAILED **"
FILTER
)

COMMON_SHELL_SYNTAX=$(cat <<'FILTER'
[filters.common-shell-syntax]
description = "Compact shell syntax-check output"
match_command = "^(bash|zsh|sh)\\s+-n\\b"
strip_ansi = true
keep_lines_matching = ["(?i)syntax error|unexpected|error|failed|warning|warn"]
truncate_lines_at = 220
max_lines = 80
filter_stderr = true
on_empty = "ok (shell syntax check passed)"

[[tests.common-shell-syntax]]
name = "empty shell syntax output is ok"
input = ""
expected = "ok (shell syntax check passed)"

[[tests.common-shell-syntax]]
name = "shell syntax error is preserved"
input = "scripts/dev: line 10: syntax error near unexpected token `fi'\n"
expected = "scripts/dev: line 10: syntax error near unexpected token `fi'"
FILTER
)

COMMON_JS_TS_CHECKS=$(cat <<'FILTER'
[filters.common-js-ts-checks]
description = "Compact JavaScript and TypeScript runtime checks"
match_command = "^(bun|deno|yarn|corepack\\s+yarn|node\\s+--test)\\b.*\\b(test|spec|check|lint|typecheck)\\b|^(npm|pnpm)\\s+(run\\s+)?(test|check|typecheck|lint)\\b"
strip_ansi = true
match_output = [{ pattern = "(?i)(all tests passed|test result: ok|\\bpassed\\b|✓)", message = "ok (js/ts checks passed)", unless = "(?i)error|failed|fatal|warning|warn|unhandled|exception" }]
keep_lines_matching = ["(?i)error|fail|failed|fatal|warning|warn|unhandled|exception|not ok|panic|timeout|timed out", "(?i)tests?\\s+(failed|passed)|test files|snapshots|duration|coverage|summary", "\\b(TS\\d+|ERR_[A-Z_]+)\\b"]
truncate_lines_at = 220
max_lines = 140
filter_stderr = true
on_empty = "ok (js/ts command produced no notable lines)"

[[tests.common-js-ts-checks]]
name = "bun test success compacts"
input = "bun test v1.1.0\n✓ src/foo.test.ts\n 1 pass\n 0 fail\nAll tests passed"
expected = "ok (js/ts checks passed)"

[[tests.common-js-ts-checks]]
name = "npm test failure is preserved"
input = "> app@1.0.0 test\nFAIL src/foo.test.ts\nError: expected true to be false\nTests: 1 failed, 2 passed"
expected = "FAIL src/foo.test.ts\nError: expected true to be false\nTests: 1 failed, 2 passed"
FILTER
)

COMMON_PYTHON_TEST=$(cat <<'FILTER'
[filters.common-python-test]
description = "Compact Python pytest and unittest output"
match_command = "^python(3)?\\s+-m\\s+(pytest|unittest)\\b"
strip_ansi = true
match_output = [{ pattern = "(?i)(=+\\s+\\d+ passed|OK)$", message = "ok (python tests passed)", unless = "(?i)error|failed|failure|warning|traceback" }]
keep_lines_matching = ["(?i)error|failed|failure|warning|traceback|assert|expected|actual", "^(FAILED|ERROR|OK|=+ .* =+)", "^E\\s+"]
truncate_lines_at = 220
max_lines = 140
filter_stderr = true
on_empty = "ok (python tests produced no notable lines)"

[[tests.common-python-test]]
name = "pytest success compacts"
input = "============================= test session starts =============================\ntests/test_profiles.py .                                                   [100%]\n============================== 1 passed in 0.12s =============================="
expected = "============================= test session starts =============================\n============================== 1 passed in 0.12s =============================="

[[tests.common-python-test]]
name = "pytest failure is preserved"
input = "FAILED tests/test_profiles.py::test_profile - AssertionError: missing vendorId\nE   AssertionError: missing vendorId\n=========================== 1 failed, 2 passed in 0.20s ======================="
expected = "FAILED tests/test_profiles.py::test_profile - AssertionError: missing vendorId\nE   AssertionError: missing vendorId\n=========================== 1 failed, 2 passed in 0.20s ======================="
FILTER
)

install_filters() {
  ensure_filters_file
  append_filter "common-swift-test" "$COMMON_SWIFT_TEST"
  append_filter "common-xcodebuild" "$COMMON_XCODEBUILD"
  append_filter "common-shell-syntax" "$COMMON_SHELL_SYNTAX"
  append_filter "common-js-ts-checks" "$COMMON_JS_TS_CHECKS"
  append_filter "common-python-test" "$COMMON_PYTHON_TEST"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  ""|-h|--help|help)
    usage
    ;;
  install-filters)
    install_filters
    ;;
  *)
    echo "ERROR: unknown rtk command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
