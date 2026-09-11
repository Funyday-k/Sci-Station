#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app|Sci-Station.dmg|Sci-Station.zip" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-install.XXXXXX")"
APPLICATIONS_DIR="$TEST_ROOT/Applications"
INSTALLED_APP="$APPLICATIONS_DIR/Sci-Station.app"
MOUNT_DIR=""
MOUNT_DEVICE=""
EXTRACT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "$EXTRACT_DIR" ]]; then
    rm -rf "$EXTRACT_DIR"
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

case "$ARTIFACT_PATH" in
  *.app)
    SOURCE_APP="$ARTIFACT_PATH"
    ;;
  *.dmg)
    MOUNT_DIR="$TEST_ROOT/mount"
    mkdir -p "$MOUNT_DIR"
    ATTACH_OUTPUT="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$ARTIFACT_PATH")"
    MOUNT_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/^\/dev\// { print $1; exit }')"
    SOURCE_APP="$MOUNT_DIR/Sci-Station.app"
    if [[ -z "$MOUNT_DEVICE" ]]; then
      echo "Unable to identify the mounted device for $ARTIFACT_PATH" >&2
      exit 1
    fi
    ;;
  *.zip)
    EXTRACT_DIR="$TEST_ROOT/extracted"
    mkdir -p "$EXTRACT_DIR"
    /usr/bin/ditto -x -k "$ARTIFACT_PATH" "$EXTRACT_DIR"
    SOURCE_APP="$EXTRACT_DIR/Sci-Station.app"
    ;;
  *)
    echo "Unsupported release artifact: $ARTIFACT_PATH" >&2
    exit 2
    ;;
esac

SOURCE_INFO_PLIST="$SOURCE_APP/Contents/Info.plist"
if [[ ! -f "$SOURCE_INFO_PLIST" ]]; then
  echo "Release artifact does not contain Sci-Station.app." >&2
  exit 1
fi
SOURCE_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_INFO_PLIST")"
SOURCE_EXECUTABLE="$SOURCE_APP/Contents/MacOS/$SOURCE_EXECUTABLE_NAME"
if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
  echo "Release artifact contains no executable app binary." >&2
  exit 1
fi

mkdir -p "$APPLICATIONS_DIR"

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
  # Unsigned CI builds still carry a linker-generated ad-hoc Mach-O signature,
  # so `codesign -dv` alone does not mean the app bundle has a valid resource
  # seal. Mirror signature verification only when the source bundle itself
  # passes the strict check. Developer ID artifacts are verified separately by
  # verify-release.sh before this installation exercise runs.
  if codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
  fi
}

echo "==> Installing into an isolated Applications directory..."
install_app
verify_installed_copy

echo "==> Exercising first launch from the installed location..."
"$ROOT_DIR/Tools/scripts/smoke-test-sidecar-runtime.sh" "$INSTALLED_APP"
"$ROOT_DIR/Tools/scripts/smoke-test-app.sh" "$INSTALLED_APP"
"$ROOT_DIR/Tools/scripts/smoke-test-ui-navigation.sh" "$INSTALLED_APP"

STALE_MARKER="$INSTALLED_APP/Contents/Resources/.sci-station-stale-install-marker"
mkdir -p "$(dirname "$STALE_MARKER")"
printf 'stale installation data\n' >"$STALE_MARKER"

echo "==> Replacing the existing installation and launching the upgrade..."
install_app
if [[ -e "$STALE_MARKER" ]]; then
  echo "Upgrade left stale files from the previous app bundle." >&2
  exit 1
fi
verify_installed_copy
"$ROOT_DIR/Tools/scripts/smoke-test-sidecar-runtime.sh" "$INSTALLED_APP"
"$ROOT_DIR/Tools/scripts/smoke-test-app.sh" "$INSTALLED_APP"
"$ROOT_DIR/Tools/scripts/smoke-test-ui-navigation.sh" "$INSTALLED_APP"

echo "Release install, first-launch, and overwrite-upgrade tests passed."
