#!/usr/bin/env bash
#
# package-beta.sh - Build a distributable Sci-Station beta build.
#
# Prefers a "Developer ID Application" certificate (cleanest: Gatekeeper accepts
# it after notarization). If none is available it falls back to whatever
# code-signing identity exists (typically "Apple Development"). If no signing
# identity exists at all it performs an ad-hoc signed build, which can still be
# packaged as a DMG but will show Gatekeeper warnings on other Macs.
#
# Output:
#   .tmp/beta-package/export/Sci-Station.app
#   .tmp/beta-package/Sci-Station-beta.zip
#   .tmp/beta-package/Sci-Station-beta.dmg   (ready to hand to a tester)
#
# Usage:
#   Tools/scripts/package-beta.sh
#   Tools/scripts/package-beta.sh "Developer ID Application: Your Name (TEAMID)"
#   SCI_STATION_SIGNING=adhoc Tools/scripts/package-beta.sh
#
set -euo pipefail

PROJECT="Sci-Station.xcodeproj"
SCHEME="Sci-Station"
CONFIG="Release"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.tmp/beta-package"
ARCHIVE_PATH="$BUILD_DIR/Sci-Station.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Sci-Station.app"
ZIP_PATH="$BUILD_DIR/Sci-Station-beta.zip"
DMG_ROOT="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/Sci-Station-beta.dmg"

cd "$ROOT_DIR"

# --- 1. Resolve a signing mode ----------------------------------------------
IDENTITY="${1:-}"
SIGNING_MODE="${SCI_STATION_SIGNING:-auto}"
EXPORT_METHOD="developer-id"
ARCHIVE_SIGNING_ARGS=()

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  IDENTITY="-"
  EXPORT_METHOD="adhoc"
elif [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"') || true
fi

if [[ "$SIGNING_MODE" != "adhoc" && -z "$IDENTITY" ]]; then
  # Fall back to any available codesigning identity (e.g. Apple Development).
  IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -o '"[^"]*"' | head -1 | tr -d '"') || true
  EXPORT_METHOD="development"
  echo "WARNING: No 'Developer ID Application' certificate found."
  echo "         Falling back to: ${IDENTITY:-<none>} (export method: development)."
  echo "         The build runs on this Mac; other testers must right-click > Open."
  echo
fi

if [[ "$EXPORT_METHOD" == "developer-id" && "$IDENTITY" != Developer\ ID\ Application:* ]]; then
  EXPORT_METHOD="development"
fi

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  EXPORT_METHOD="adhoc"
  echo "WARNING: No code-signing identity available at all."
  echo "         Falling back to ad-hoc signing. The DMG can be shared, but testers"
  echo "         must grant macOS permission to open an unidentified developer app."
  echo
fi

TEAM_ID=$(echo "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{8,\}\)).*/\1/p')

case "$EXPORT_METHOD" in
  developer-id)
    echo "Using Developer ID signing identity: $IDENTITY"
    ARCHIVE_SIGNING_ARGS=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$IDENTITY"
      DEVELOPMENT_TEAM="$TEAM_ID"
    )
    ;;
  development)
    echo "Using development signing identity: $IDENTITY"
    ARCHIVE_SIGNING_ARGS=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$IDENTITY"
      DEVELOPMENT_TEAM="$TEAM_ID"
    )
    ;;
  adhoc)
    echo "Using ad-hoc signing (no Apple Developer account or certificate required)."
    ARCHIVE_SIGNING_ARGS=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY=-
      DEVELOPMENT_TEAM=
      OTHER_CODE_SIGN_FLAGS=--timestamp=none
    )
    ;;
esac

# --- 2. Clean + archive ------------------------------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving ($CONFIG)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  "${ARCHIVE_SIGNING_ARGS[@]}"

# --- 3. Export ---------------------------------------------------------------
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Sci-Station.app"

if [[ "$EXPORT_METHOD" == "developer-id" ]]; then
  EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
  cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF
  echo "==> Exporting (developer-id)..."
  if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST"; then
    echo "exportArchive failed; using the archived .app product directly."
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVED_APP" "$APP_PATH"
  fi
elif [[ "$EXPORT_METHOD" == "development" ]]; then
  # Development signing: the archived product is already signed correctly, and
  # `exportArchive` only knows how to re-sign with a "Mac Development" cert that
  # an "Apple Development" account does not have. Use the archived app directly.
  echo "==> Using the archived (development-signed) .app product directly..."
  mkdir -p "$EXPORT_PATH"
  cp -R "$ARCHIVED_APP" "$APP_PATH"
else
  # Ad-hoc signing: no export step or provisioning profile is needed. The app is
  # intentionally not notarized and will not pass Gatekeeper on first launch.
  echo "==> Using the archived (ad-hoc signed) .app product directly..."
  mkdir -p "$EXPORT_PATH"
  cp -R "$ARCHIVED_APP" "$APP_PATH"
fi

# --- 4. Verify ---------------------------------------------------------------
echo "==> Verifying signature, entitlements, and Gatekeeper policy..."
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Runtime" || true
echo "--- entitlements ---"
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true
echo "--- deep verify ---"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
echo "--- gatekeeper (a 'rejected' result is expected without a notarized Developer ID build) ---"
spctl -a -vvv "$APP_PATH" || true

# --- 5. Zip + DMG for handoff -----------------------------------------------
echo "==> Zipping..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Creating DMG..."
rm -rf "$DMG_ROOT" "$DMG_PATH"
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
echo "Beta app exported to: $APP_PATH"
echo "Shareable zip:        $ZIP_PATH"
echo "Shareable DMG:        $DMG_PATH"
echo
if [[ "$EXPORT_METHOD" == "developer-id" ]]; then
  echo "OPTIONAL (deferred for beta) - notarize so Gatekeeper accepts it cleanly:"
  echo "  xcrun notarytool submit \"$DMG_PATH\" --keychain-profile <profile> --wait"
  echo "  xcrun stapler staple \"$APP_PATH\""
elif [[ "$EXPORT_METHOD" == "development" ]]; then
  echo "This build is signed for development only. Tell testers to right-click the"
  echo "app and choose Open the first time to bypass the Gatekeeper warning."
else
  echo "This build is ad-hoc signed and not notarized. Tell testers to right-click the"
  echo "app and choose Open, or run this after dragging the app to /Applications:"
  echo "  xattr -dr com.apple.quarantine /Applications/Sci-Station.app"
fi
