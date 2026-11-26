#!/bin/bash
# Build local candidate containers using the release archive conventions.
set -euo pipefail

INPUT_APP=""
if [[ $# -eq 2 && "$1" == --app ]]; then
	INPUT_APP="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
elif [[ $# -ne 0 ]]; then
	printf 'Usage: %s [--app /path/to/Sci-Station.app]\n' "$0" >&2
	exit 2
fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/scripts/macos-release-artifacts.sh"
VERSION="$(cat "$ROOT/VERSION")"
if [[ "${SCI_STATION_VERSION:-$VERSION}" != "$VERSION" ]]; then
	printf 'The requested workstation package version must match VERSION.\n' >&2
	exit 1
fi

BASE="${SCI_STATION_RELEASE_BUILD_DIR:-$ROOT/.tmp}"
mkdir -p "$BASE"
BASE="$(cd "$BASE" && pwd -P)"
BUILD_DIR="$(mktemp -d "$BASE/workstation-package.XXXXXX")"
APP="$BUILD_DIR/Sci-Station.app"
complete=false
trap 'if ! "$complete"; then rm -rf "$BUILD_DIR"; fi' EXIT

if [[ -n "$INPUT_APP" ]]; then
	"$ROOT/Tools/scripts/verify-release.sh" "$INPUT_APP"
	/usr/bin/ditto "$INPUT_APP" "$APP"
else
	APP_OUTPUT="$APP" "$ROOT/packaging/macos/build.sh"
fi
NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
NAME="Sci-Station-$VERSION-$NUMBER-macOS-arm64"
ZIP="$BUILD_DIR/$NAME.zip"
DMG="$BUILD_DIR/$NAME.dmg"
release_zip "$APP" "$ZIP"
release_dmg "$APP" "$DMG" "$BUILD_DIR/dmg-root"
release_checksum "$ZIP" >"$ZIP.sha256"
release_checksum "$DMG" >"$DMG.sha256"

SCI_STATION_BUILD_NUMBER="$NUMBER" "$ROOT/Tools/scripts/verify-release.sh" "$ZIP"
SCI_STATION_BUILD_NUMBER="$NUMBER" "$ROOT/Tools/scripts/verify-release.sh" "$DMG"
rm -rf "$BUILD_DIR/dmg-root"
write_release_outputs "$APP" "$ZIP" "$DMG"
complete=true
printf 'Workstation candidate ZIP: %s\nWorkstation candidate DMG: %s\n' "$ZIP" "$DMG"
