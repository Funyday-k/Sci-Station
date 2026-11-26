#!/usr/bin/env bash
# Enforce the desktop statement coverage baseline from a Go test profile.
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/coverage.out" >&2
  exit 2
fi

summary="$(go tool cover -func="$1" | awk '$1 == "total:" && $2 == "(statements)" && $3 ~ /^[0-9]+([.][0-9]+)?%$/ { print $3 }')"
if [[ -z "$summary" ]]; then
  echo "The Go profile does not report statement coverage." >&2
  exit 1
fi

awk -v actual="${summary%%%}" -v minimum="74.0" 'BEGIN {
  printf "Go statement coverage: %.1f%% (minimum %.1f%%)\n", actual, minimum
  exit (actual + 0 < minimum + 0)
}'
