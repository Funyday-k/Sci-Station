#!/usr/bin/env bash
# Build, Developer ID sign, notarize, staple, and verify public release artifacts.
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
IDENTITY="${SCI_STATION_DEVELOPER_ID_APPLICATION:-}"
TEAM_ID="${SCI_STATION_TEAM_ID:-}"
NOTARY_PROFILE="${SCI_STATION_NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEY_PATH="${SCI_STATION_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${SCI_STATION_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${SCI_STATION_NOTARY_ISSUER_ID:-}"

if [[ -z "$IDENTITY" || -z "$TEAM_ID" ]]; then
  echo "SCI_STATION_DEVELOPER_ID_APPLICATION and SCI_STATION_TEAM_ID are required." >&2
  exit 2
fi

NOTARY_ARGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" ]]; then
  if [[ ! -f "$NOTARY_KEY_PATH" ]]; then
    echo "SCI_STATION_NOTARY_KEY_PATH does not exist." >&2
    exit 2
  fi
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo "Configure a notary keychain profile or the API key path/id/issuer triplet." >&2
  exit 2
fi

cd "$ROOT_DIR"

VERSION="${SCI_STATION_VERSION:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ MARKETING_VERSION =/{print $3; exit}')}"
BUILD_NUMBER="${SCI_STATION_BUILD_NUMBER:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings | awk '/ CURRENT_PROJECT_VERSION =/{print $3; exit}')}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid release version/build number: $VERSION ($BUILD_NUMBER)" >&2
  exit 1
fi
Tools/scripts/check-release-build-number.sh "v$VERSION" "$BUILD_NUMBER"

ARTIFACT_BASENAME="Sci-Station-${VERSION}-${BUILD_NUMBER}-macOS-arm64"
APP_NOTARY_ZIP="$BUILD_DIR/${ARTIFACT_BASENAME}-notary.zip"
ZIP_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.zip"
DMG_PATH="$BUILD_DIR/${ARTIFACT_BASENAME}.dmg"
NOTARY_LOG_DIR="$BUILD_DIR/notary-logs"

notarize() {
  local artifact="$1"
  local label="$2"
  local log_path="$NOTARY_LOG_DIR/$label.json"
  local status

  print_notary_failure_log() {
    local submission_id
    local detail_log_path="$NOTARY_LOG_DIR/$label-details.json"

    submission_id="$(/usr/bin/plutil -extract id raw "$log_path" 2>/dev/null || true)"
    if [[ -z "$submission_id" ]]; then
      echo "Notary submission did not return an ID; no detailed log is available." >&2
      return
    fi
    if xcrun notarytool log "${NOTARY_ARGS[@]}" "$submission_id" "$detail_log_path"; then
      cat "$detail_log_path" >&2
    else
      echo "Unable to retrieve the detailed notarization log for $submission_id." >&2
    fi
  }

  echo "==> Submitting $label for notarization..."
  if ! xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait --output-format json >"$log_path"; then
    if [[ -f "$log_path" ]]; then
      cat "$log_path" >&2
    else
      echo "notarytool did not produce a submission response for $label." >&2
    fi
    print_notary_failure_log
    return 1
  fi
  status="$(/usr/bin/plutil -extract status raw "$log_path" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization did not finish as Accepted (${status:-missing status})." >&2
    if [[ -f "$log_path" ]]; then
      cat "$log_path" >&2
    fi
    print_notary_failure_log
    return 1
  fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH" "$NOTARY_LOG_DIR"

echo "==> Archiving $ARTIFACT_BASENAME with Developer ID..."
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
  "CODE_SIGN_IDENTITY=$IDENTITY" \
  "CODE_SIGN_IDENTITY[sdk=macosx*]=$IDENTITY" \
  "DEVELOPMENT_TEAM=$TEAM_ID" \
  "MARKETING_VERSION=$VERSION" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  ENABLE_HARDENED_RUNTIME=YES \
  "OTHER_CODE_SIGN_FLAGS=--timestamp" \
  archive

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Sci-Station.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "Archive completed without the expected app product: $ARCHIVED_APP" >&2
  exit 1
fi
/usr/bin/ditto "$ARCHIVED_APP" "$APP_PATH"

Tools/scripts/stage-sidecar-runtime.sh "$APP_PATH"
Tools/scripts/sign-sidecar-runtime.sh "$APP_PATH" "$IDENTITY"
Tools/scripts/smoke-test-sidecar-runtime.sh "$APP_PATH"
Tools/scripts/smoke-test-app.sh "$APP_PATH"
Tools/scripts/smoke-test-ui-navigation.sh "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
signature_details="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$signature_details" != *"Authority=Developer ID Application:"* || "$signature_details" != *"TeamIdentifier=$TEAM_ID"* || "$signature_details" != *"runtime"* ]]; then
  echo "The archived app is missing the expected Developer ID, team, or hardened runtime signature." >&2
  exit 1
fi

echo "==> Notarizing and stapling the app..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_NOTARY_ZIP"
notarize "$APP_NOTARY_ZIP" app
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f "$APP_NOTARY_ZIP"

SCI_STATION_TEAM_ID="$TEAM_ID" \
SCI_STATION_VERSION="$VERSION" \
SCI_STATION_BUILD_NUMBER="$BUILD_NUMBER" \
  Tools/scripts/verify-release.sh "$APP_PATH"
Tools/scripts/smoke-test-app.sh "$APP_PATH"
Tools/scripts/smoke-test-ui-navigation.sh "$APP_PATH"

echo "==> Creating final ZIP..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
SCI_STATION_TEAM_ID="$TEAM_ID" \
SCI_STATION_VERSION="$VERSION" \
SCI_STATION_BUILD_NUMBER="$BUILD_NUMBER" \
  Tools/scripts/verify-release.sh "$ZIP_PATH"
Tools/scripts/test-release-install.sh "$ZIP_PATH"

echo "==> Creating, signing, and notarizing final DMG..."
mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP_PATH" "$DMG_ROOT/Sci-Station.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Sci-Station" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
notarize "$DMG_PATH" dmg
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

SCI_STATION_TEAM_ID="$TEAM_ID" \
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
echo "Developer ID identity: $IDENTITY"
echo "Team ID: $TEAM_ID"
