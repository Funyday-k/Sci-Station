#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app|Sci-Station.dmg|Sci-Station.zip" >&2
  exit 2
fi

ARTIFACT_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EXPECTED_BUNDLE_ID="${SCI_STATION_BUNDLE_ID:-Lingyu-Xia.Sci-Station}"
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
  return 0
}
trap cleanup EXIT

verify_boolean_entitlement() {
  local code_path="$1" entitlement_key="$2" expected_value="$3"
  local entitlements escaped_key actual_value
  entitlements="$(codesign -d --entitlements :- "$code_path" 2>/dev/null)"
  escaped_key="${entitlement_key//./\\.}"
  actual_value="$(printf '%s' "$entitlements" | /usr/bin/plutil -extract "$escaped_key" raw -o - - 2>/dev/null || true)"
  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "Signed code is missing entitlement $entitlement_key=$expected_value: $code_path" >&2
    exit 1
  fi
}

verify_adhoc_signature() {
  local path="$1" details
  codesign --verify --strict --verbose=2 "$path"
  details="$(codesign -dv --verbose=4 "$path" 2>&1)"
  if [[ "$details" != *"Signature=adhoc"* ]]; then
    echo "Artifact is not ad-hoc signed: $path" >&2
    exit 1
  fi
  if [[ "$details" != *"runtime"* ]]; then
    echo "Artifact signature does not enable hardened runtime: $path" >&2
    exit 1
  fi
}

verify_app() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  local executable_name executable_path bundle_id bundle_version bundle_build_number architectures

  [[ -f "$info_plist" ]] || { echo "Missing app Info.plist: $info_plist" >&2; exit 1; }
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
  executable_path="$app_path/Contents/MacOS/$executable_name"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  bundle_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"

  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || { echo "Unexpected bundle identifier: $bundle_id" >&2; exit 1; }
  [[ -z "$EXPECTED_VERSION" || "$bundle_version" == "$EXPECTED_VERSION" ]] || { echo "Unexpected app version: $bundle_version" >&2; exit 1; }
  [[ -z "$EXPECTED_BUILD_NUMBER" || "$bundle_build_number" == "$EXPECTED_BUILD_NUMBER" ]] || { echo "Unexpected app build number: $bundle_build_number" >&2; exit 1; }
  [[ -x "$executable_path" ]] || { echo "Missing app executable: $executable_path" >&2; exit 1; }

  "$ROOT_DIR/Tools/scripts/verify-macos-deployment-target.sh" "$app_path"
  architectures="$(lipo -archs "$executable_path")"
  case " $architectures " in *" arm64 "*) ;; *) echo "App executable is missing arm64: $architectures" >&2; exit 1 ;; esac

  codesign --verify --deep --strict --verbose=2 "$app_path"
  verify_adhoc_signature "$app_path"
  verify_boolean_entitlement "$app_path" "com.apple.security.app-sandbox" "true"

  local sidecar_python="$app_path/Contents/Resources/SidecarRuntime/bin/python3.12"
  [[ -x "$sidecar_python" ]] || { echo "Release app is missing the bundled sidecar Python runtime." >&2; exit 1; }
  verify_adhoc_signature "$sidecar_python"
  verify_boolean_entitlement "$sidecar_python" "com.apple.security.app-sandbox" "true"
  verify_boolean_entitlement "$sidecar_python" "com.apple.security.inherit" "true"

  # Certificate-free releases are intentionally not notarized. Record the
  # platform trust result for diagnostics, but rejection is expected for a
  # quarantined download and must not invalidate bundle-integrity checks.
  if spctl --assess --type execute --verbose=4 "$app_path"; then
    echo "Gatekeeper accepted this local artifact."
  else
    echo "Gatekeeper did not trust the certificate-free artifact; this is expected for downloaded releases."
  fi
  "$ROOT_DIR/Tools/scripts/smoke-test-sidecar-runtime.sh" "$app_path"
}

case "$ARTIFACT_PATH" in
  *.app)
    verify_app "$ARTIFACT_PATH"
    ;;
  *.dmg)
    hdiutil verify "$ARTIFACT_PATH"
    MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-release.XXXXXX")"
    attach_output="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$ARTIFACT_PATH")"
    MOUNT_DEVICE="$(printf '%s\n' "$attach_output" | awk '/^\/dev\// { print $1; exit }')"
    [[ -n "$MOUNT_DEVICE" && -d "$MOUNT_DIR/Sci-Station.app" ]] || { echo "The release DMG does not contain the expected Sci-Station.app." >&2; exit 1; }
    verify_app "$MOUNT_DIR/Sci-Station.app"
    ;;
  *.zip)
    EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-release-zip.XXXXXX")"
    /usr/bin/ditto -x -k "$ARTIFACT_PATH" "$EXTRACT_DIR"
    [[ -d "$EXTRACT_DIR/Sci-Station.app" ]] || { echo "The release ZIP does not contain the expected Sci-Station.app." >&2; exit 1; }
    verify_app "$EXTRACT_DIR/Sci-Station.app"
    ;;
  *)
    echo "Unsupported release artifact: $ARTIFACT_PATH" >&2
    exit 2
    ;;
esac

echo "Certificate-free release verification passed: $ARTIFACT_PATH"
exit 0
