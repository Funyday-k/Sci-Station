#!/usr/bin/env bash
set -euo pipefail

MAX_TRACKED_FILE_BYTES="${MAX_TRACKED_FILE_BYTES:-10485760}"
failed=0

forbidden_pattern='(^|/)(\.build|\.derivedData|DerivedData|build|Build|dist|release)(/|$)|\.(app|xcarchive|dSYM)(/|$)|\.(dmg|zip|tar\.gz)$'
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    echo "Tracked generated artifact: $path" >&2
    failed=1
done < <(git ls-files | grep -E "$forbidden_pattern" || true)

while IFS= read -r -d '' path; do
    size="$(wc -c < "$path" | tr -d ' ')"
    if (( size > MAX_TRACKED_FILE_BYTES )); then
        echo "Tracked file exceeds $MAX_TRACKED_FILE_BYTES bytes: $path ($size bytes)" >&2
        failed=1
    fi
done < <(git ls-files -z)

git diff --check

if (( failed != 0 )); then
    echo "Repository hygiene check failed." >&2
    exit 1
fi

echo "Repository hygiene check passed."
