#!/usr/bin/env bash
# Reject public releases whose CFBundleVersion does not exceed the prior stable release.
set -euo pipefail

ROOT_DIR="${SCI_STATION_RELEASE_REPOSITORY:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_FILE="${SCI_STATION_PROJECT_FILE:-Sci-Station.xcodeproj/project.pbxproj}"
CURRENT_TAG="${1:-${SCI_STATION_RELEASE_TAG:-}}"
CURRENT_BUILD_NUMBER="${2:-${SCI_STATION_BUILD_NUMBER:-}}"

fail() {
  echo "Release build-number gate failed: $*" >&2
  exit 1
}

if [[ ! "$CURRENT_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  fail "expected a stable release tag such as v0.2.0, got '${CURRENT_TAG:-<empty>}'."
fi
current_major="${BASH_REMATCH[1]}"
current_minor="${BASH_REMATCH[2]}"
current_patch="${BASH_REMATCH[3]}"
if [[ ! "$CURRENT_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  fail "CFBundleVersion must contain decimal digits, got '${CURRENT_BUILD_NUMBER:-<empty>}'."
fi
if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  fail "$ROOT_DIR is not a Git repository."
fi

previous_tag=""
previous_major=0
previous_minor=0
previous_patch=0

is_less_than_current() {
  local major="$1"
  local minor="$2"
  local patch="$3"

  if ((10#$major != 10#$current_major)); then
    ((10#$major < 10#$current_major))
  elif ((10#$minor != 10#$current_minor)); then
    ((10#$minor < 10#$current_minor))
  else
    ((10#$patch < 10#$current_patch))
  fi
}

is_greater_than_previous() {
  local major="$1"
  local minor="$2"
  local patch="$3"

  if [[ -z "$previous_tag" ]]; then
    return 0
  fi
  if ((10#$major != 10#$previous_major)); then
    ((10#$major > 10#$previous_major))
  elif ((10#$minor != 10#$previous_minor)); then
    ((10#$minor > 10#$previous_minor))
  else
    ((10#$patch > 10#$previous_patch))
  fi
}

while IFS= read -r candidate_tag; do
  if [[ ! "$candidate_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
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

if ! previous_project="$(git -C "$ROOT_DIR" show "$previous_tag:$PROJECT_FILE" 2>/dev/null)"; then
  fail "unable to read $PROJECT_FILE from prior release $previous_tag."
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
if [[ ! "$previous_build_number" =~ ^[0-9]+$ ]]; then
  fail "prior release $previous_tag has invalid CFBundleVersion '$previous_build_number'."
fi

if ((10#$CURRENT_BUILD_NUMBER <= 10#$previous_build_number)); then
  fail "$CURRENT_TAG build $CURRENT_BUILD_NUMBER must be greater than $previous_tag build $previous_build_number."
fi

echo "$CURRENT_TAG build $CURRENT_BUILD_NUMBER is greater than $previous_tag build $previous_build_number."
