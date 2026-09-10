#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app [codesign-identity]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
IDENTITY="${2:-${SCI_STATION_DEVELOPER_ID_APPLICATION:--}}"
RUNTIME_ROOT="$APP_PATH/Contents/Resources/SidecarRuntime"
PYTHON_EXECUTABLE="$RUNTIME_ROOT/bin/python3.12"
APP_ENTITLEMENTS="$ROOT_DIR/Sci-Station/Sci-Station.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/Sci-Station/SidecarRuntime.entitlements"

if [[ ! -f "$APP_PATH/Contents/Info.plist" || ! -x "$PYTHON_EXECUTABLE" ]]; then
  echo "A staged Sci-Station app and sidecar runtime are required before signing." >&2
  exit 1
fi
if [[ ! -f "$APP_ENTITLEMENTS" || ! -f "$HELPER_ENTITLEMENTS" ]]; then
  echo "Required app or helper entitlements are missing." >&2
  exit 1
fi

if [[ "$IDENTITY" == "-" ]]; then
  TIMESTAMP_ARGS=(--timestamp=none)
else
  TIMESTAMP_ARGS=(--timestamp)
fi

assert_boolean_entitlement() {
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
    echo "Signed code is missing entitlement $entitlement_key=$expected_value: $code_path" >&2
    exit 1
  fi
}

echo "==> Signing bundled sidecar Mach-O files..."
while IFS= read -r -d '' candidate; do
  if [[ "$candidate" == "$PYTHON_EXECUTABLE" ]]; then
    continue
  fi
  if file -b "$candidate" | grep -q 'Mach-O'; then
    codesign \
      --force \
      "${TIMESTAMP_ARGS[@]}" \
      --options runtime \
      --sign "$IDENTITY" \
      "$candidate"
  fi
done < <(find "$RUNTIME_ROOT" -type f -print0)

codesign \
  --force \
  "${TIMESTAMP_ARGS[@]}" \
  --options runtime \
  --entitlements "$HELPER_ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$PYTHON_EXECUTABLE"

echo "==> Re-signing the app after runtime staging..."
codesign \
  --force \
  "${TIMESTAMP_ARGS[@]}" \
  --options runtime \
  --entitlements "$APP_ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
assert_boolean_entitlement "$APP_PATH" "com.apple.security.app-sandbox" "true"
assert_boolean_entitlement "$PYTHON_EXECUTABLE" "com.apple.security.app-sandbox" "true"
assert_boolean_entitlement "$PYTHON_EXECUTABLE" "com.apple.security.inherit" "true"
echo "Sidecar runtime and app signatures verified."
