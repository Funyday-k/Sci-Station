#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Sci-Station"
BUNDLE_ID="Lingyu-Xia.Sci-Station"
DEVELOPMENT_TEAM="${SCI_STATION_DEVELOPMENT_TEAM:-K7A7Y3LPZF}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Sci-Station.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/XcodeDerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY=- \
    build

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        codesign --verify --deep --strict "$APP_BUNDLE"
        SIGNATURE_DETAILS="$(codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1)"
        if [[ "$SIGNATURE_DETAILS" != *"Signature=adhoc"* ]]; then
            echo "Expected Sign to Run Locally (ad-hoc) signature." >&2
            exit 1
        fi
        open_app
        for _ in {1..40}; do
            if pgrep -x "$APP_NAME" >/dev/null; then
                exit 0
            fi
            sleep 0.25
        done
        echo "$APP_NAME did not remain running after launch." >&2
        exit 1
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
