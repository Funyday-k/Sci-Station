#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/previous.zip|.dmg /path/to/candidate.zip|.dmg" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/Tools/scripts/macos-release-artifacts.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-install.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
APPLICATIONS_DIR="$TEST_ROOT/Applications"
INSTALLED_APP="$APPLICATIONS_DIR/Sci-Station.app"

cleanup() {
  if close_release_app; then
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$APPLICATIONS_DIR"
select_source_app() {
  SOURCE_APP="$1"
  SOURCE_INFO_PLIST="$SOURCE_APP/Contents/Info.plist"
  if [[ ! -f "$SOURCE_INFO_PLIST" ]]; then
    echo "Release artifact does not contain the expected Info.plist." >&2
    exit 1
  fi
  SOURCE_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_INFO_PLIST")"
  SOURCE_EXECUTABLE="$SOURCE_APP/Contents/MacOS/$SOURCE_EXECUTABLE_NAME"
  if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
    echo "Release artifact contains no executable app binary." >&2
    exit 1
  fi
}

install_app() {
  local staged_app="$APPLICATIONS_DIR/.Sci-Station.installing.app"

  rm -rf "$staged_app"
  /usr/bin/ditto "$SOURCE_APP" "$staged_app"
  if [[ ! -x "$staged_app/Contents/MacOS/$SOURCE_EXECUTABLE_NAME" ]]; then
    echo "The staged installation is not executable." >&2
    exit 1
  fi

  rm -rf "$INSTALLED_APP"
  mv "$staged_app" "$INSTALLED_APP"
}

verify_installed_copy() {
  local installed_executable="$INSTALLED_APP/Contents/MacOS/$SOURCE_EXECUTABLE_NAME"

  if ! cmp -s "$SOURCE_INFO_PLIST" "$INSTALLED_APP/Contents/Info.plist"; then
    echo "Installed Info.plist differs from the release artifact." >&2
    exit 1
  fi
  if ! cmp -s "$SOURCE_EXECUTABLE" "$installed_executable"; then
    echo "Installed executable differs from the release artifact." >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
}

stage_release_archive() {
  local input="$1" stage="$2" expected_build="$3" artifact
  artifact="$(cd "$(dirname "$input")" && pwd -P)/$(basename "$input")"
  if [[ "$artifact" != *.zip && "$artifact" != *.dmg ]]; then
    printf 'Release install validation requires a ZIP or DMG and its SHA-256 sidecar.\n' >&2
    exit 2
  fi
  SCI_STATION_BUILD_NUMBER="$expected_build" "$ROOT_DIR/Tools/scripts/verify-release.sh" "$artifact"
  open_release_app "$artifact" "$stage/container"
  /usr/bin/ditto "$RELEASE_SOURCE_APP" "$stage/Sci-Station.app"
  close_release_app
}

previous="$TEST_ROOT/previous"
candidate="$TEST_ROOT/candidate"
stage_release_archive "$1" "$previous" ""
stage_release_archive "$2" "$candidate" "${SCI_STATION_BUILD_NUMBER:-}"
previous_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$previous/Sci-Station.app/Contents/Info.plist")"
candidate_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate/Sci-Station.app/Contents/Info.plist")"
if ! python3 -c 'import sys; sys.exit(int(sys.argv[2]) <= int(sys.argv[1]))' "$previous_build" "$candidate_build"; then
  printf 'The candidate build must advance from %s to a greater number (got %s).\n' "$previous_build" "$candidate_build" >&2
  exit 1
fi
smoke="$ROOT_DIR/tests/package-install-smoke.py"
select_source_app "$previous/Sci-Station.app"
install_app
verify_installed_copy
python3 "$smoke" "$INSTALLED_APP" "$TEST_ROOT" initial
/usr/bin/ditto "$TEST_ROOT/research-root" "$TEST_ROOT/pre-upgrade-backup"

stale_marker="$INSTALLED_APP/Contents/Resources/.sci-station-stale-install-marker"
printf 'stale installation fixture\n' >"$stale_marker"
select_source_app "$candidate/Sci-Station.app"
install_app
[[ ! -e "$stale_marker" ]] || { printf 'Upgrade left a stale bundle file.\n' >&2; exit 1; }
verify_installed_copy
python3 "$smoke" "$INSTALLED_APP" "$TEST_ROOT" upgraded

# Restore the known-good snapshot into a sibling fixture. Keep the upgraded
# fixture intact and exercise the previous bundle again at the install path.
/usr/bin/ditto "$TEST_ROOT/pre-upgrade-backup" "$TEST_ROOT/restored-root"
select_source_app "$previous/Sci-Station.app"
install_app
verify_installed_copy
python3 "$smoke" "$INSTALLED_APP" "$TEST_ROOT" rollback
printf 'Release install, overwrite upgrade, and rollback passed (%s → %s → %s).\n' \
  "$previous_build" "$candidate_build" "$previous_build"
