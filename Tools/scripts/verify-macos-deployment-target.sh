#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXPECTED_TARGET="${SCI_STATION_MINIMUM_MACOS_VERSION:-15.0}"

normalize_version() {
  local version="$1"

  if [[ ! "$version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "Invalid macOS deployment target: $version" >&2
    return 1
  fi

  awk -F. '{ printf "%d.%d.%d\n", $1, ($2 == "" ? 0 : $2), ($3 == "" ? 0 : $3) }' <<<"$version"
}

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing app Info.plist: $INFO_PLIST" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing app executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

EXPECTED_NORMALIZED="$(normalize_version "$EXPECTED_TARGET")"
PLIST_TARGET="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$PLIST_TARGET" ]]; then
  echo "App Info.plist does not declare LSMinimumSystemVersion." >&2
  exit 1
fi
if [[ "$(normalize_version "$PLIST_TARGET")" != "$EXPECTED_NORMALIZED" ]]; then
  echo "Unexpected LSMinimumSystemVersion: $PLIST_TARGET (expected $EXPECTED_TARGET)." >&2
  exit 1
fi

LOAD_COMMANDS="$(/usr/bin/otool -l "$EXECUTABLE_PATH")"
MACHO_TARGETS="$({
  printf '%s\n' "$LOAD_COMMANDS" | awk '
    $1 == "cmd" {
      relevant = ($2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX")
      next
    }
    relevant && ($1 == "minos" || $1 == "version") {
      print $2
      relevant = 0
    }
  '
})"
if [[ -z "$MACHO_TARGETS" ]]; then
  echo "App executable does not declare a macOS deployment target: $EXECUTABLE_PATH" >&2
  exit 1
fi

while IFS= read -r target; do
  if [[ "$(normalize_version "$target")" != "$EXPECTED_NORMALIZED" ]]; then
    echo "Unexpected Mach-O deployment target: $target (expected $EXPECTED_TARGET)." >&2
    exit 1
  fi
done <<<"$MACHO_TARGETS"

version_is_at_most_expected() {
  local actual="$1"
  local expected="$2"
  awk -F. -v actual="$actual" -v expected="$expected" '
    BEGIN {
      split(actual, a, ".")
      split(expected, e, ".")
      for (i = 1; i <= 3; i++) {
        av = (a[i] == "" ? 0 : a[i]) + 0
        ev = (e[i] == "" ? 0 : e[i]) + 0
        if (av < ev) exit 0
        if (av > ev) exit 1
      }
      exit 0
    }
  '
}

MACHO_COUNT=0
while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q 'Mach-O'; then
    continue
  fi
  MACHO_COUNT=$((MACHO_COUNT + 1))
  candidate_targets="$({
    /usr/bin/otool -l "$candidate" | awk '
      $1 == "cmd" {
        relevant = ($2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX")
        next
      }
      relevant && ($1 == "minos" || $1 == "version") {
        print $2
        relevant = 0
      }
    '
  })"
  if [[ -z "$candidate_targets" ]]; then
    echo "Mach-O file does not declare a macOS deployment target: $candidate" >&2
    exit 1
  fi
  while IFS= read -r candidate_target; do
    if ! version_is_at_most_expected "$candidate_target" "$EXPECTED_TARGET"; then
      echo "Bundled Mach-O requires macOS $candidate_target, above supported $EXPECTED_TARGET: $candidate" >&2
      exit 1
    fi
  done <<<"$candidate_targets"
done < <(find "$APP_PATH/Contents" -type f -print0)

echo "macOS deployment target verification passed: $EXPECTED_TARGET ($MACHO_COUNT Mach-O files checked)"
