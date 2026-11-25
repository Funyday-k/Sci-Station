#!/bin/bash
# Validate a complete workstation bundle without starting it.
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
	printf 'Usage: %s /path/to/Sci-Station.app\n' "$0" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/sci-station"
IDENTIFIER=com.funyday.scistation.desktop

require_plist_string() {
	local actual
	actual="$(/usr/libexec/PlistBuddy -c "Print :$1" "$PLIST")"
	if [[ "$actual" != "$2" ]]; then
		printf 'Unexpected %s in the workstation bundle: %s (expected %s).\n' "$1" "$actual" "$2" >&2
		exit 1
	fi
}

/usr/bin/plutil -lint "$PLIST"
require_plist_string CFBundleIdentifier "$IDENTIFIER"
require_plist_string CFBundleName Sci-Station
require_plist_string CFBundleDisplayName Sci-Station
require_plist_string CFBundleExecutable sci-station
require_plist_string CFBundlePackageType APPL
require_plist_string CFBundleIconFile roundtable.icns
require_plist_string CFBundleShortVersionString "$(cat "$ROOT/../../VERSION")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ || "$BUILD_NUMBER" != "${SCI_STATION_BUILD_NUMBER:-$BUILD_NUMBER}" ]]; then
	printf 'Unexpected workstation build number: %s.\n' "$BUILD_NUMBER" >&2
	exit 1
fi

if [[ ! -x "$EXECUTABLE" || "$(/usr/bin/lipo -archs "$EXECUTABLE")" != arm64 ]]; then
	printf 'Expected a single Apple Silicon workstation executable.\n' >&2
	exit 1
fi
"$ROOT/../../Tools/scripts/verify-macos-deployment-target.sh" "$APP"

cmp "$ROOT/macos/roundtable.icns" "$APP/Contents/Resources/roundtable.icns"
cmp "$ROOT/magpie/sci-station.agent.js" "$APP/Contents/Resources/sci-station.agent.js"
printf '%s\n' 'Info.plist' 'MacOS/sci-station' 'PkgInfo' 'Resources/roundtable.icns' \
	'Resources/sci-station.agent.js' '_CodeSignature/CodeResources' |
	LC_ALL=C sort | diff -u - <(cd "$APP/Contents" && find . ! -type d -print | sed 's|^\./||' | LC_ALL=C sort)

/usr/bin/codesign --verify --deep --strict -R="identifier \"$IDENTIFIER\"" "$APP"
SIGNATURE="$(/usr/bin/codesign --display --verbose=4 "$APP" 2>&1)"
if ! grep -qx 'Signature=adhoc' <<<"$SIGNATURE" || ! grep -q '^CodeDirectory .*flags=.*(.*runtime' <<<"$SIGNATURE"; then
	printf 'Expected an ad-hoc signature with hardened runtime.\n' >&2
	exit 1
fi
ENTITLEMENTS="$(/usr/bin/codesign --display --entitlements - "$APP" 2>/dev/null)"
if [[ -n "$ENTITLEMENTS" ]]; then
	printf 'Unexpected signing entitlements in the workstation candidate.\n' >&2
	exit 1
fi
printf 'Verified %s\n' "$APP"
