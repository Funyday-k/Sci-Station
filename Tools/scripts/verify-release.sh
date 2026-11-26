#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app|Sci-Station.dmg|Sci-Station.zip" >&2
  exit 2
fi

ARTIFACT_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/Tools/scripts/macos-release-artifacts.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-release.XXXXXX")"

cleanup() {
  if close_release_app; then
    rm -rf "$TEST_ROOT"
  fi
  return 0
}
trap cleanup EXIT

case "$ARTIFACT_PATH" in
  *.dmg|*.zip) verify_release_checksum "$ARTIFACT_PATH" ;;
esac
if [[ "$ARTIFACT_PATH" == *.dmg ]]; then
  /usr/bin/hdiutil verify "$ARTIFACT_PATH"
fi

open_release_app "$ARTIFACT_PATH" "$TEST_ROOT"
"$ROOT_DIR/packaging/macos/verify.sh" "$RELEASE_SOURCE_APP"
if spctl --assess --type execute --verbose=4 "$RELEASE_SOURCE_APP"; then
  echo "Gatekeeper accepted this local artifact."
else
  echo "Gatekeeper requires approval for this certificate-free artifact."
fi
close_release_app

echo "Certificate-free release verification passed: $ARTIFACT_PATH"
