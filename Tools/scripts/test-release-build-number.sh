#!/usr/bin/env bash
# Exercise initial, increasing, duplicate, decreasing, and malformed build-number paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/Tools/scripts/check-release-build-number.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-build-number.XXXXXX")"
REPOSITORY="$TEST_ROOT/repository"
BROKEN_REPOSITORY="$TEST_ROOT/broken-repository"
PROJECT_FILE="Sci-Station.xcodeproj/project.pbxproj"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

write_build_number() {
  local build_number="$1"
  mkdir -p "$REPOSITORY/Sci-Station.xcodeproj"
  printf 'CURRENT_PROJECT_VERSION = %s;\nCURRENT_PROJECT_VERSION = %s;\n' \
    "$build_number" "$build_number" >"$REPOSITORY/$PROJECT_FILE"
}

commit_and_tag() {
  local message="$1"
  local tag="$2"
  git -C "$REPOSITORY" add "$PROJECT_FILE"
  git -C "$REPOSITORY" commit -q -m "$message"
  git -C "$REPOSITORY" tag "$tag"
}

expect_failure() {
  local expected_message="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    echo "Failure did not contain '$expected_message':" >&2
    echo "$output" >&2
    exit 1
  fi
}

git init -q "$REPOSITORY"
git -C "$REPOSITORY" config user.name "Sci-Station Release Test"
git -C "$REPOSITORY" config user.email "release-test@example.invalid"

write_build_number 1
commit_and_tag "Initial release" v0.1.0
SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.1.0 1

write_build_number 2
commit_and_tag "Second release" v0.2.0
SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 2
expect_failure "must be greater than v0.1.0 build 1" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 1
expect_failure "must be greater than v0.1.0 build 1" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 0
expect_failure "expected a stable release tag" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0-rc.1 3
expect_failure "CFBundleVersion must contain decimal digits" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0 two

write_build_number 9
commit_and_tag "Ninth minor release" v0.9.0
write_build_number 10
commit_and_tag "Tenth minor release" v0.10.0
SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.11.0 11
expect_failure "must be greater than v0.10.0 build 10" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.11.0 10

git init -q "$BROKEN_REPOSITORY"
git -C "$BROKEN_REPOSITORY" config user.name "Sci-Station Release Test"
git -C "$BROKEN_REPOSITORY" config user.email "release-test@example.invalid"
mkdir -p "$BROKEN_REPOSITORY/Sci-Station.xcodeproj"
printf 'CURRENT_PROJECT_VERSION = one;\n' >"$BROKEN_REPOSITORY/$PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" add "$PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" commit -q -m "Malformed prior release"
git -C "$BROKEN_REPOSITORY" tag v0.1.0
printf 'CURRENT_PROJECT_VERSION = 2;\n' >"$BROKEN_REPOSITORY/$PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" add "$PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" commit -q -m "Candidate release"
expect_failure "has invalid CFBundleVersion 'one'" \
  env SCI_STATION_RELEASE_REPOSITORY="$BROKEN_REPOSITORY" "$GATE" v0.2.0 2

echo "Release build-number gate tests passed."
