#!/usr/bin/env bash
# Exercise initial, increasing, duplicate, decreasing, and malformed build-number paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/Tools/scripts/check-release-build-number.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-build-number.XXXXXX")"
REPOSITORY="$TEST_ROOT/repository"
BROKEN_REPOSITORY="$TEST_ROOT/broken-repository"
LEGACY_PROJECT_FILE="Sci-Station.xcodeproj/project.pbxproj"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

write_legacy_build_number() {
  local build_number="$1"
  mkdir -p "$REPOSITORY/Sci-Station.xcodeproj"
  printf 'CURRENT_PROJECT_VERSION = %s;\nCURRENT_PROJECT_VERSION = %s;\n' \
    "$build_number" "$build_number" >"$REPOSITORY/$LEGACY_PROJECT_FILE"
}

write_build_number() {
  printf '%s\n' "$1" >"$REPOSITORY/BUILD_NUMBER"
}

commit_and_tag() {
  local message="$1"
  local tag="$2"
  git -C "$REPOSITORY" add -A
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

write_legacy_build_number 1
commit_and_tag "Initial release" v0.1.0
SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.1.0 1

write_build_number 2
commit_and_tag "Second release" v0.2.0
SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 2
expect_failure "must be greater than v0.1.0 build 1" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 1
expect_failure "CFBundleVersion must be a positive decimal integer" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.2.0 0
expect_failure "expected a stable release tag" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0-rc.1 3
expect_failure "CFBundleVersion must be a positive decimal integer" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0 two

SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0 3
expect_failure "must be greater than v0.2.0 build 2" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0 2
expect_failure "CFBundleVersion must be a positive decimal integer" \
  env SCI_STATION_RELEASE_REPOSITORY="$REPOSITORY" "$GATE" v0.3.0 03

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
printf 'CURRENT_PROJECT_VERSION = one;\n' >"$BROKEN_REPOSITORY/$LEGACY_PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" add "$LEGACY_PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" commit -q -m "Malformed prior release"
git -C "$BROKEN_REPOSITORY" tag v0.1.0
printf 'CURRENT_PROJECT_VERSION = 2;\n' >"$BROKEN_REPOSITORY/$LEGACY_PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" add "$LEGACY_PROJECT_FILE"
git -C "$BROKEN_REPOSITORY" commit -q -m "Candidate release"
expect_failure "has invalid CFBundleVersion 'one'" \
  env SCI_STATION_RELEASE_REPOSITORY="$BROKEN_REPOSITORY" "$GATE" v0.2.0 2

printf 'one\n' >"$BROKEN_REPOSITORY/BUILD_NUMBER"
git -C "$BROKEN_REPOSITORY" add BUILD_NUMBER
git -C "$BROKEN_REPOSITORY" commit -q -m "Malformed current build-number source"
git -C "$BROKEN_REPOSITORY" tag v0.2.0
expect_failure "v0.2.0 has invalid CFBundleVersion 'one'" \
  env SCI_STATION_RELEASE_REPOSITORY="$BROKEN_REPOSITORY" "$GATE" v0.3.0 3

echo "Release build-number gate tests passed."
