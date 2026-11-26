#!/usr/bin/env bash
# Build or stage the signed macOS release bundle and verify its ZIP and DMG.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT_DIR/packaging/macos/package.sh" "$@"
