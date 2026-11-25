#!/bin/bash
# Build a local, ad-hoc signed macOS application. No installation is required.
set -euo pipefail
cd "$(dirname "$0")/../.."
GO="${GO:-go}"
export MACOSX_DEPLOYMENT_TARGET=12.0
export CGO_CFLAGS="-mmacosx-version-min=12.0 ${CGO_CFLAGS:-}"
export CGO_LDFLAGS="-mmacosx-version-min=12.0 ${CGO_LDFLAGS:-}"
APP="${APP_OUTPUT:-Sci-Station.app}"
APP_PARENT="$(dirname "$APP")"
APP_NAME="$(basename "$APP")"
if [[ "$APP_NAME" != ?*.app || "$APP_NAME" == ".app" || -L "$APP" ]]; then
	printf 'Choose a local .app bundle as the build output.\n' >&2
	exit 1
fi
mkdir -p "$APP_PARENT"
if [[ "${1:-}" != "--output-locked" ]]; then
	exec /usr/bin/lockf -t 120 "$APP_PARENT/.$APP_NAME.build-lock" /bin/bash ./packaging/macos/build.sh --output-locked
fi
if [[ -e "$APP" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)" != "com.funyday.scistation.desktop" ]]; then
	printf 'Existing output is not a Sci-Station app: %s\n' "$APP" >&2
	exit 1
fi
STAGE_ROOT="$(/usr/bin/mktemp -d "$APP_PARENT/.roundtable-build.XXXXXX")"
STAGED_APP="$STAGE_ROOT/$APP_NAME"
BACKUP_APP="$STAGE_ROOT/previous.app"
HAD_BACKUP=0
cleanup() {
	status=$?
	preserve_stage=0
	if [[ "$HAD_BACKUP" == 1 && -e "$BACKUP_APP" && ! -e "$APP" ]]; then
		if ! mv "$BACKUP_APP" "$APP"; then
			printf 'ERROR: could not restore previous app; it remains at %s\n' "$BACKUP_APP" >&2
			preserve_stage=1
		fi
	fi
	if [[ "$preserve_stage" == 0 ]]; then rm -rf "$STAGE_ROOT"; fi
	exit "$status"
}
trap cleanup EXIT
CONTENTS="$STAGED_APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
"$GO" build -tags production -trimpath -ldflags '-s -w' -o "$CONTENTS/MacOS/sci-station" .
cp packaging/macos/Info.plist "$CONTENTS/Info.plist"
cp packaging/macos/roundtable.icns "$CONTENTS/Resources/roundtable.icns"
cp packaging/magpie/sci-station.agent.js "$CONTENTS/Resources/sci-station.agent.js"
printf 'APPL????' > "$CONTENTS/PkgInfo"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"
/usr/bin/codesign --force --sign - "$STAGED_APP"
/usr/bin/codesign --verify --strict "$STAGED_APP"
if [[ -e "$APP" ]]; then
	mv "$APP" "$BACKUP_APP"
	HAD_BACKUP=1
fi
if ! mv "$STAGED_APP" "$APP"; then
	if [[ "$HAD_BACKUP" == 1 ]]; then mv "$BACKUP_APP" "$APP"; HAD_BACKUP=0; fi
	printf 'ERROR: could not install verified app at %s\n' "$APP" >&2
	exit 1
fi
if [[ "$HAD_BACKUP" == 1 ]]; then rm -rf "$BACKUP_APP"; HAD_BACKUP=0; fi
printf 'Built %s\n' "$APP"
