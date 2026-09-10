#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app|Sci-Station.dmg|Sci-Station.zip" >&2
  exit 2
fi

ARTIFACT_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EXPECTED_BUNDLE_ID="${SCI_STATION_BUNDLE_ID:-Lingyu-Xia.Sci-Station}"
EXPECTED_TEAM_ID="${SCI_STATION_TEAM_ID:-}"
EXPECTED_VERSION="${SCI_STATION_VERSION:-}"
EXPECTED_BUILD_NUMBER="${SCI_STATION_BUILD_NUMBER:-}"
MOUNT_DIR=""
MOUNT_DEVICE=""
EXTRACT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "$MOUNT_DIR" ]]; then
    rm -rf "$MOUNT_DIR"
  fi
  if [[ -n "$EXTRACT_DIR" ]]; then
    rm -rf "$EXTRACT_DIR"
  fi
}
trap cleanup EXIT

verify_boolean_entitlement() {
  local code_path="$1"
  local entitlement_key="$2"
  local expected_value="$3"
  local entitlements
  local escaped_key
  local actual_value

  entitlements="$(codesign -d --entitlements :- "$code_path" 2>/dev/null)"
  escaped_key="${entitlement_key//./\\.}"
  actual_value="$(printf '%s' "$entitlements" | /usr/bin/plutil -extract "$escaped_key" raw -o - - 2>/dev/null || true)"
  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "Artifact is missing entitlement $entitlement_key=$expected_value: $code_path" >&2
    exit 1
  fi
}

verify_developer_id_signature() {
  local path="$1"
  local details
  details="$(codesign -dv --verbose=4 "$path" 2>&1)"

  if [[ "$details" != *"Authority=Developer ID Application:"* ]]; then
    echo "Artifact is not signed with a Developer ID Application identity: $path" >&2
    exit 1
  fi
  if [[ -n "$EXPECTED_TEAM_ID" && "$details" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]; then
    echo "Artifact TeamIdentifier does not match SCI_STATION_TEAM_ID: $path" >&2
    exit 1
  fi
}

verify_app() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  local executable_name
  local executable_path
  local bundle_id
  local bundle_version
  local bundle_build_number
  local architectures
  local details

  if [[ ! -f "$info_plist" ]]; then
    echo "Missing app Info.plist: $info_plist" >&2
    exit 1
  fi

  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
  executable_path="$app_path/Contents/MacOS/$executable_name"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  bundle_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Unexpected bundle identifier: $bundle_id" >&2
    exit 1
  fi
  if [[ -n "$EXPECTED_VERSION" && "$bundle_version" != "$EXPECTED_VERSION" ]]; then
    echo "Unexpected app version: $bundle_version" >&2
    exit 1
  fi
  if [[ -n "$EXPECTED_BUILD_NUMBER" && "$bundle_build_number" != "$EXPECTED_BUILD_NUMBER" ]]; then
    echo "Unexpected app build number: $bundle_build_number" >&2
    exit 1
  fi
  if [[ ! -x "$executable_path" ]]; then
    echo "Missing app executable: $executable_path" >&2
    exit 1
  fi

  "$ROOT_DIR/Tools/scripts/verify-macos-deployment-target.sh" "$app_path"

  architectures="$(lipo -archs "$executable_path")"
  case " $architectures " in
    *" arm64 "*) ;;
    *)
      echo "App executable is missing arm64: $architectures" >&2
      exit 1
      ;;
  esac

  codesign --verify --deep --strict --verbose=2 "$app_path"
  verify_developer_id_signature "$app_path"
  verify_boolean_entitlement "$app_path" "com.apple.security.app-sandbox" "true"
  details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
  if [[ "$details" != *"runtime"* ]]; then
    echo "App signature does not enable hardened runtime." >&2
    exit 1
  fi

  sidecar_python="$app_path/Contents/Resources/SidecarRuntime/bin/python3.12"
  if [[ ! -x "$sidecar_python" ]]; then
    echo "Release app is missing the bundled sidecar Python runtime." >&2
    exit 1
  fi
  codesign --verify --strict --verbose=2 "$sidecar_python"
  verify_boolean_entitlement "$sidecar_python" "com.apple.security.app-sandbox" "true"
  verify_boolean_entitlement "$sidecar_python" "com.apple.security.inherit" "true"
  sidecar_details="$(codesign -dv --verbose=4 "$sidecar_python" 2>&1)"
  if [[ "$sidecar_details" != *"Authority=Developer ID Application:"* || "$sidecar_details" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* || "$sidecar_details" != *"runtime"* ]]; then
    echo "Bundled sidecar runtime is missing the expected Developer ID or hardened runtime signature." >&2
    exit 1
  fi

  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=4 "$app_path"
  "$ROOT_DIR/Tools/scripts/smoke-test-sidecar-runtime.sh" "$app_path"
}

case "$ARTIFACT_PATH" in
  *.app)
    verify_app "$ARTIFACT_PATH"
    ;;
  *.dmg)
    codesign --verify --strict --verbose=2 "$ARTIFACT_PATH"
    verify_developer_id_signature "$ARTIFACT_PATH"
    xcrun stapler validate "$ARTIFACT_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$ARTIFACT_PATH"

    MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-release.XXXXXX")"
    attach_output="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$ARTIFACT_PATH")"
    MOUNT_DEVICE="$(printf '%s\n' "$attach_output" | awk '/^\/dev\// { print $1; exit }')"
    if [[ -z "$MOUNT_DEVICE" || ! -d "$MOUNT_DIR/Sci-Station.app" ]]; then
      echo "The release DMG does not contain the expected Sci-Station.app." >&2
      exit 1
    fi
    verify_app "$MOUNT_DIR/Sci-Station.app"
    ;;
  *.zip)
    EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-release-zip.XXXXXX")"
    /usr/bin/ditto -x -k "$ARTIFACT_PATH" "$EXTRACT_DIR"
    if [[ ! -d "$EXTRACT_DIR/Sci-Station.app" ]]; then
      echo "The release ZIP does not contain the expected Sci-Station.app." >&2
      exit 1
    fi
    verify_app "$EXTRACT_DIR/Sci-Station.app"
    ;;
  *)
    echo "Unsupported release artifact: $ARTIFACT_PATH" >&2
    exit 2
    ;;
esac

echo "Release verification passed: $ARTIFACT_PATH"
