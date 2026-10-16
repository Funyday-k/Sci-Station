#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
coverage_json="${1:-}"
minimum_percent="${2:-14.0}"

if [[ ! "$minimum_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: minimum coverage must be a non-negative number, got '$minimum_percent'" >&2
  exit 2
fi

if [[ -z "$coverage_json" ]]; then
  coverage_candidates=()
  while IFS= read -r candidate; do
    coverage_candidates+=("$candidate")
  done < <(find "$repo_root/.build" -type f -path '*/debug/codecov/SciStationCore.json' -print 2>/dev/null)

  if (( ${#coverage_candidates[@]} > 1 )); then
    echo "error: multiple Swift coverage reports found; pass the intended JSON path explicitly" >&2
    printf '  %s\n' "${coverage_candidates[@]}" >&2
    exit 2
  fi
  coverage_json="${coverage_candidates[0]:-}"
elif [[ "$coverage_json" != /* ]]; then
  coverage_json="$repo_root/$coverage_json"
fi

if [[ -z "$coverage_json" || ! -f "$coverage_json" ]]; then
  echo "error: Swift coverage report not found: $coverage_json" >&2
  echo "Run 'swift test --enable-code-coverage' before this check." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to inspect the Swift coverage report" >&2
  exit 2
fi

source_prefix="$repo_root/Sci-Station/"
summary="$({
  jq -r --arg source_prefix "$source_prefix" '
    [
      .data[].files[]
      | select(.filename | startswith($source_prefix))
      | select(.filename | contains("/.build/") | not)
      | select(.filename | contains("/Tests/") | not)
      | select(.filename | contains("/Tools/SciStationCoreTestRunner/") | not)
    ] as $files
    | ($files | map(.summary.lines.count) | add // 0) as $total
    | ($files | map(.summary.lines.covered) | add // 0) as $covered
    | [$files | length, $total, $covered]
    | @tsv
  ' "$coverage_json"
} 2>&1)" || {
  echo "error: unable to parse Swift coverage report: $coverage_json" >&2
  echo "$summary" >&2
  exit 2
}

IFS=$'\t' read -r file_count total_lines covered_lines <<<"$summary"
if (( file_count == 0 || total_lines == 0 )); then
  echo "error: coverage report contains no project source lines under $source_prefix" >&2
  exit 2
fi

actual_percent="$(awk -v covered="$covered_lines" -v total="$total_lines" 'BEGIN { printf "%.2f", covered * 100 / total }')"
printf 'Swift Core line coverage: %s/%s lines (%s%%), minimum %s%% across %s files\n' \
  "$covered_lines" "$total_lines" "$actual_percent" "$minimum_percent" "$file_count"

if ! awk -v covered="$covered_lines" -v total="$total_lines" -v minimum="$minimum_percent" \
  'BEGIN { exit !((covered * 100 / total) + 0.0000001 >= minimum) }'; then
  echo "error: Swift Core line coverage fell below the required baseline" >&2
  exit 1
fi
