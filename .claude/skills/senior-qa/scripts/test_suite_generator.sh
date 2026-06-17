#!/usr/bin/env bash
#
# test_suite_generator.sh — scaffold a unit-test file for a JS/TS source file.
#
# Inspects exported symbols (function/class/const) and emits a sibling
# *.test.* file containing one describe block per export plus a checklist of
# canonical case categories. Detects whether the project uses Vitest or Jest
# from package.json; falls back to Vitest syntax (compatible with both).
#
# Usage:
#   scripts/test_suite_generator.sh path/to/source.ts [--framework vitest|jest] [--force]

set -euo pipefail

print_help() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

SOURCE=""
FRAMEWORK=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework) FRAMEWORK="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) SOURCE="$1"; shift ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  echo "error: source file required" >&2
  print_help
  exit 2
fi

if [[ ! -f "$SOURCE" ]]; then
  echo "error: $SOURCE not found" >&2
  exit 1
fi

# Detect framework if not provided.
if [[ -z "$FRAMEWORK" ]]; then
  if [[ -f package.json ]] && grep -q '"vitest"' package.json; then
    FRAMEWORK=vitest
  elif [[ -f package.json ]] && grep -q '"jest"' package.json; then
    FRAMEWORK=jest
  else
    FRAMEWORK=vitest
  fi
fi

# Derive test path: foo.ts -> foo.test.ts (preserve extension).
dir="$(dirname "$SOURCE")"
base="$(basename "$SOURCE")"
name="${base%.*}"
ext="${base##*.}"
TEST_PATH="$dir/$name.test.$ext"

if [[ -e "$TEST_PATH" && $FORCE -ne 1 ]]; then
  echo "error: $TEST_PATH already exists (pass --force to overwrite)" >&2
  exit 1
fi

# Extract exported symbols (best-effort, regex-based).
mapfile -t EXPORTS < <(
  grep -E '^export (default |async )?(function|class|const|let|var) [A-Za-z_$][A-Za-z0-9_$]*' "$SOURCE" \
    | sed -E 's/^export (default |async )?(function|class|const|let|var) ([A-Za-z_$][A-Za-z0-9_$]*).*/\3/' \
    | sort -u
)

import_specifier="./$name"

{
  if [[ "$FRAMEWORK" == "vitest" ]]; then
    echo "import { describe, it, expect, beforeEach, vi } from \"vitest\";"
  else
    echo "import { describe, it, expect, beforeEach, jest } from \"@jest/globals\";"
  fi

  if (( ${#EXPORTS[@]} > 0 )); then
    printf 'import { %s } from "%s";\n' "$(IFS=, ; echo "${EXPORTS[*]}")" "$import_specifier"
  else
    echo "// TODO: no named exports detected — import default or update this file."
    echo "// import x from \"$import_specifier\";"
  fi
  echo

  if (( ${#EXPORTS[@]} == 0 )); then
    EXPORTS=("$name")
  fi

  for sym in "${EXPORTS[@]}"; do
    cat <<EOF
describe("$sym", () => {
  beforeEach(() => {
    // arrange shared setup; prefer factories over inline literals
  });

  // happy path
  it.todo("returns the expected result for a typical input");

  // edge / boundary
  it.todo("handles empty / zero / minimum input");
  it.todo("handles maximum / overflow input");

  // error / failure
  it.todo("rejects invalid input with a clear error");
  it.todo("propagates downstream failures without swallowing them");

  // security / authz (delete if N/A)
  it.todo("denies access for unauthenticated callers");
});

EOF
  done
} > "$TEST_PATH"

echo "wrote $TEST_PATH ($FRAMEWORK)"
echo "exports detected: ${EXPORTS[*]:-<none>}"
echo
echo "Next steps:"
echo "  1. Replace it.todo(...) with real cases — risk-first."
echo "  2. Run the suite to confirm the file is picked up."
echo "  3. Verify each test fails when you break the code path it covers."
