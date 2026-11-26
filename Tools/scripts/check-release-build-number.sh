#!/usr/bin/env bash
# Reject public releases whose CFBundleVersion does not exceed the prior stable release.
set -euo pipefail

ROOT_DIR="${SCI_STATION_RELEASE_REPOSITORY:-$(cd "$(dirname "$0")/../.." && pwd)}"
LEGACY_PROJECT_FILE="Sci-Station.xcodeproj/project.pbxproj"
export LC_ALL=C
CURRENT_TAG="${1:-${SCI_STATION_RELEASE_TAG:-}}"
CURRENT_BUILD_NUMBER="${2:-${SCI_STATION_BUILD_NUMBER:-}}"

fail() {
  echo "Release build-number gate failed: $*" >&2
  exit 1
}

if [[ ! "$CURRENT_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "expected a stable release tag such as v0.2.0, got '${CURRENT_TAG:-<empty>}'."
fi
current_major="${BASH_REMATCH[1]}"
current_minor="${BASH_REMATCH[2]}"
current_patch="${BASH_REMATCH[3]}"
if [[ ! "$CURRENT_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  fail "CFBundleVersion must be a positive decimal integer, got '${CURRENT_BUILD_NUMBER:-<empty>}'."
fi
if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  fail "$ROOT_DIR is not a Git repository."
fi

previous_tag=""
previous_major=0
previous_minor=0
previous_patch=0

number_is_less() {
  local left="$1" right="$2"
  if (( ${#left} != ${#right} )); then
    (( ${#left} < ${#right} ))
  else
    [[ "$left" < "$right" ]]
  fi
}

is_less_than_current() {
  local major="$1"
  local minor="$2"
  local patch="$3"

  if [[ "$major" != "$current_major" ]]; then
    number_is_less "$major" "$current_major"
  elif [[ "$minor" != "$current_minor" ]]; then
    number_is_less "$minor" "$current_minor"
  else
    number_is_less "$patch" "$current_patch"
  fi
}

is_greater_than_previous() {
  local major="$1"
  local minor="$2"
  local patch="$3"

  if [[ -z "$previous_tag" ]]; then
    return 0
  fi
  if [[ "$major" != "$previous_major" ]]; then
    number_is_less "$previous_major" "$major"
  elif [[ "$minor" != "$previous_minor" ]]; then
    number_is_less "$previous_minor" "$minor"
  else
    number_is_less "$previous_patch" "$patch"
  fi
}

while IFS= read -r candidate_tag; do
  if [[ ! "$candidate_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    continue
  fi
  candidate_major="${BASH_REMATCH[1]}"
  candidate_minor="${BASH_REMATCH[2]}"
  candidate_patch="${BASH_REMATCH[3]}"
  if is_less_than_current "$candidate_major" "$candidate_minor" "$candidate_patch" \
    && is_greater_than_previous "$candidate_major" "$candidate_minor" "$candidate_patch"; then
    previous_tag="$candidate_tag"
    previous_major="$candidate_major"
    previous_minor="$candidate_minor"
    previous_patch="$candidate_patch"
  fi
done < <(git -C "$ROOT_DIR" tag --list 'v*')

if [[ -z "$previous_tag" ]]; then
  echo "No prior stable release tag precedes $CURRENT_TAG; allowing initial public release build $CURRENT_BUILD_NUMBER."
  exit 0
fi

if git -C "$ROOT_DIR" cat-file -e "$previous_tag:BUILD_NUMBER" 2>/dev/null; then
  previous_build_number="$(git -C "$ROOT_DIR" show "$previous_tag:BUILD_NUMBER")"
else
  # Tags published before the desktop cutover store the number in the Xcode project.
  if ! previous_project="$(git -C "$ROOT_DIR" show "$previous_tag:$LEGACY_PROJECT_FILE" 2>/dev/null)"; then
    fail "unable to read BUILD_NUMBER or $LEGACY_PROJECT_FILE from prior release $previous_tag."
  fi
  previous_build_numbers="$(
    printf '%s\n' "$previous_project" \
      | awk -F= '/CURRENT_PROJECT_VERSION[[:space:]]*=/{value=$2; sub(/;.*/, "", value); gsub(/[[:space:]]/, "", value); if (value != "") print value}' \
      | sort -u
  )"
  previous_build_count="$(printf '%s\n' "$previous_build_numbers" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$previous_build_count" != "1" ]]; then
    fail "expected one CURRENT_PROJECT_VERSION in $previous_tag, found $previous_build_count distinct values."
  fi
  previous_build_number="$previous_build_numbers"
fi
if [[ ! "$previous_build_number" =~ ^[1-9][0-9]*$ ]]; then
  fail "prior release $previous_tag has invalid CFBundleVersion '$previous_build_number'."
fi

if ! number_is_less "$previous_build_number" "$CURRENT_BUILD_NUMBER"; then
  fail "$CURRENT_TAG build $CURRENT_BUILD_NUMBER must be greater than $previous_tag build $previous_build_number."
fi

echo "$CURRENT_TAG build $CURRENT_BUILD_NUMBER is greater than $previous_tag build $previous_build_number."
