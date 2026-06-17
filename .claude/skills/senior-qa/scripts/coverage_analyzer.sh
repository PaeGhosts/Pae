#!/usr/bin/env bash
#
# coverage_analyzer.sh — run the project's coverage command and rank the
# lowest-covered files by risk score.
#
# The risk score is (uncovered_lines * sqrt(file_size_in_lines)). Big,
# under-tested files float to the top. The script reads coverage-final.json
# from coverage/ (Vitest, Jest, and c8/v8 emit this by default).
#
# Usage:
#   scripts/coverage_analyzer.sh [--cmd "npm run test:coverage"] [--top 20] [--json coverage/coverage-final.json]

set -euo pipefail

print_help() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

CMD=""
TOP=20
JSON_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    --cmd) CMD="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    --json) JSON_PATH="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Pick a runner if --cmd not given.
if [[ -z "$CMD" ]]; then
  if [[ -f package.json ]]; then
    if grep -q '"test:coverage"' package.json; then
      CMD="npm run test:coverage"
    elif grep -q '"coverage"' package.json; then
      CMD="npm run coverage"
    elif grep -q '"vitest"' package.json; then
      CMD="npx vitest run --coverage"
    elif grep -q '"jest"' package.json; then
      CMD="npx jest --coverage"
    else
      echo "error: could not detect a coverage command; pass --cmd" >&2
      exit 2
    fi
  else
    echo "error: no package.json found; pass --cmd" >&2
    exit 2
  fi
fi

echo "▶ running: $CMD"
eval "$CMD"

if [[ -z "$JSON_PATH" ]]; then
  for candidate in coverage/coverage-final.json coverage/coverage-summary.json; do
    if [[ -f "$candidate" ]]; then
      JSON_PATH="$candidate"
      break
    fi
  done
fi

if [[ -z "$JSON_PATH" || ! -f "$JSON_PATH" ]]; then
  echo "error: could not locate coverage JSON; pass --json" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required to parse coverage JSON" >&2
  exit 1
fi

echo
echo "▶ top $TOP files ranked by risk (uncovered lines × √size):"

node - "$JSON_PATH" "$TOP" <<'NODE'
const fs = require("fs");
const [, , jsonPath, topRaw] = process.argv;
const top = Number(topRaw) || 20;
const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const rows = [];
for (const [file, entry] of Object.entries(data)) {
  // coverage-final.json shape: { statementMap, s: {id: hitCount}, ... }
  if (!entry || typeof entry !== "object" || !entry.s) continue;
  const total = Object.keys(entry.s).length;
  if (total === 0) continue;
  const covered = Object.values(entry.s).filter((n) => n > 0).length;
  const uncovered = total - covered;
  const pct = total === 0 ? 0 : (covered / total) * 100;
  const risk = uncovered * Math.sqrt(total);
  rows.push({ file, total, covered, uncovered, pct, risk });
}

rows.sort((a, b) => b.risk - a.risk);

const shortPath = (p) => p.replace(process.cwd() + "/", "");
console.log(
  ["risk", "pct", "uncovered", "total", "file"]
    .map((s) => s.padEnd(9))
    .join("") + "\n" + "-".repeat(80)
);
for (const r of rows.slice(0, top)) {
  console.log(
    [
      r.risk.toFixed(0).padEnd(9),
      (r.pct.toFixed(1) + "%").padEnd(9),
      String(r.uncovered).padEnd(9),
      String(r.total).padEnd(9),
      shortPath(r.file),
    ].join("")
  );
}
NODE

echo
echo "Interpretation:"
echo "  - Top of the list = best ROI for new tests."
echo "  - 100% rows that look critical are also worth a glance: high line cov can hide low branch cov."
