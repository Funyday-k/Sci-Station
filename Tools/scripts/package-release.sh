#!/usr/bin/env bash
# Build, ad-hoc sign, verify, and package certificate-free public release artifacts.
set -euo pipefail

PROJECT="Sci-Station.xcodeproj"
SCHEME="Sci-Station"
CONFIG="Release"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${SCI_STATION_RELEASE_BUILD_DIR:-$ROOT_DIR/.tmp/release-package}"
ARCHIVE_PATH="$BUILD_DIR/Sci-Station.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Sci-Station.app"
DMG_ROOT="$BUILD_DIR/dmg-root"

cd "$ROOT_DIR"

VERSION="${SCI_STATION_VERSION:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ MARKETING_VERSION =/{print $3; exit}')}"
BUILD_NUMBER="${SCI_STATION_BUILD_NUMBER:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ CURRENT_PROJECT_VERSION =/{print $3; exit}')}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid release version/build number: $VERSION ($BUILD_NUMBER)" >&2
  exit 1
fi
Tools/scripts/check-release-build-number.sh "v$VERSION" "$BUILD_NUMBER"

ARTIFACT_BASENAME="Sci-Station-${VERSION}-${BUILD_NUMBER}-macOS-arm64"
ZIP_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.zip"
DMG_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

echo "==> Archiving certificate-free $ARTIFACT_BASENAME..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  "MARKETING_VERSION=$VERSION" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  archive

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Sci-Station.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "Archive completed without the expected app product: $ARCHIVED_APP" >&2
  exit 1
fi
/usr/bin/ditto "$ARCHIVED_APP" "$APP_PATH"

# The sidecar is staged after Xcode archives the app, so sign every nested
# Mach-O and then re-sign the enclosing app with the ad-hoc identity.
Tools/scripts/stage-sidecar-runtime.sh "$APP_PATH"
Tools/scripts/sign-sidecar-runtime.sh "$APP_PATH" "-"
Tools/scripts/smoke-test-sidecar-runtime.sh "$APP_PATH"
Tools/scripts/smoke-test-app.sh "$APP_PATH"
Tools/scripts/smoke-test-ui-navigation.sh "$APP_PATH"

SCI_STATION_VERSION="$VERSION" \
SCI_STATION_BUILD_NUMBER="$BUILD_NUMBER" \
  Tools/scripts/verify-release.sh "$APP_PATH"

echo "==> Creating final ZIP..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
SCI_STATION_VERSION="$VERSION" \
SCI_STATION_BUILD_NUMBER="$BUILD_NUMBER" \
  Tools/scripts/verify-release.sh "$ZIP_PATH"
Tools/scripts/test-release-install.sh "$ZIP_PATH"

echo "==> Creating final DMG..."
mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP_PATH" "$DMG_ROOT/Sci-Station.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Sci-Station" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

SCI_STATION_VERSION="$VERSION" \
SCI_STATION_BUILD_NUMBER="$BUILD_NUMBER" \
  Tools/scripts/verify-release.sh "$DMG_PATH"
Tools/scripts/test-release-install.sh "$DMG_PATH"

(
  cd "$BUILD_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" >"$(basename "$ZIP_PATH").sha256"
  shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$DMG_PATH").sha256"
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "app_path=$APP_PATH"
    echo "zip_path=$ZIP_PATH"
    echo "dmg_path=$DMG_PATH"
    echo "zip_checksum_path=$ZIP_PATH.sha256"
    echo "dmg_checksum_path=$DMG_PATH.sha256"
  } >>"$GITHUB_OUTPUT"
fi

echo
echo "App: $APP_PATH"
echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
echo "Signing: ad-hoc (certificate-free)"
echo "Notarization: not performed"
echo "Gatekeeper: first-launch warning is expected on downloaded builds"
