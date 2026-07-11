#!/usr/bin/env bash
# Build a certificate-free Apple Silicon Sci-Station beta package.
#
# Default: ad-hoc signing (preserves sandbox entitlements, no certificate).
# Optional: SCI_STATION_SIGNING=unsigned for a completely unsigned bundle.
set -euo pipefail

PROJECT="Sci-Station.xcodeproj"
SCHEME="Sci-Station"
CONFIG="Release"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.tmp/beta-package"
ARCHIVE_PATH="$BUILD_DIR/Sci-Station.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Sci-Station.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
SIGNING_MODE="${SCI_STATION_SIGNING:-adhoc}"

cd "$ROOT_DIR"

case "$SIGNING_MODE" in
  adhoc)
    SIGNING_ARGS=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY=-
      DEVELOPMENT_TEAM=
      OTHER_CODE_SIGN_FLAGS=--timestamp=none
    )
    ;;
  unsigned)
    SIGNING_ARGS=(
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
      DEVELOPMENT_TEAM=
    )
    ;;
  *)
    echo "Unsupported SCI_STATION_SIGNING=$SIGNING_MODE (expected adhoc or unsigned)." >&2
    exit 2
    ;;
esac

VERSION="${SCI_STATION_VERSION:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ MARKETING_VERSION =/{print $3; exit}')}"
BUILD_NUMBER="${SCI_STATION_BUILD_NUMBER:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ CURRENT_PROJECT_VERSION =/{print $3; exit}')}"
if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Unable to resolve app version/build number." >&2
  exit 1
fi

ARTIFACT_BASENAME="Sci-Station-${VERSION}-${BUILD_NUMBER}-macOS-arm64"
ZIP_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.zip"
DMG_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving $ARTIFACT_BASENAME ($SIGNING_MODE)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  archive \
  "${SIGNING_ARGS[@]}"

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Sci-Station.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "Archive completed without the expected app product: $ARCHIVED_APP" >&2
  exit 1
fi

mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVED_APP" "$APP_PATH"

echo "==> Verifying Apple Silicon architecture..."
ARCHS_OUTPUT="$(lipo -archs "$APP_PATH/Contents/MacOS/Sci-Station")"
case " $ARCHS_OUTPUT " in
  *" arm64 "*) ;;
  *)
    echo "Packaged executable is missing arm64: $ARCHS_OUTPUT" >&2
    exit 1
    ;;
esac

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  echo "==> Verifying ad-hoc signature and entitlements..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -d --entitlements :- "$APP_PATH"
else
  echo "==> Verifying the bundle is unsigned..."
  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "Expected an unsigned app, but codesign verification succeeded." >&2
    exit 1
  fi
fi

echo "==> Recording Gatekeeper status (rejection is expected without Developer ID)..."
if spctl -a -vvv "$APP_PATH"; then
  echo "Gatekeeper accepted the certificate-free build on this Mac."
else
  echo "Gatekeeper rejected the certificate-free build as expected; users can use Finder's Open command."
fi

echo "==> Creating ZIP..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Creating DMG..."
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/Sci-Station.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Sci-Station Beta" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "App: $APP_PATH"
echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
echo "Signing mode: $SIGNING_MODE"
