#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

RUNTIME_RELEASE="20260718"
PYTHON_VERSION="3.12.13"
RUNTIME_ARCHIVE_NAME="cpython-${PYTHON_VERSION}+${RUNTIME_RELEASE}-aarch64-apple-darwin-install_only_stripped.tar.gz"
RUNTIME_ARCHIVE_SHA256="9a1e9e06175c10efd8378b904b07fa21bd791ab3345d7cdffeb4a76c9ff55903"
RUNTIME_ARCHIVE_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RUNTIME_RELEASE}/cpython-${PYTHON_VERSION}%2B${RUNTIME_RELEASE}-aarch64-apple-darwin-install_only_stripped.tar.gz"
RUNTIME_CACHE_DIR="${SCI_STATION_RUNTIME_CACHE_DIR:-$ROOT_DIR/.tmp/runtime-cache}"
RUNTIME_ARCHIVE="${SCI_STATION_RUNTIME_ARCHIVE:-$RUNTIME_CACHE_DIR/$RUNTIME_ARCHIVE_NAME}"

RESOURCES_DIR="$APP_PATH/Contents/Resources"
RUNTIME_DESTINATION="$RESOURCES_DIR/SidecarRuntime"
SIDECAR_DESTINATION="$RESOURCES_DIR/AgentRuntime"
SOURCE_PACKAGE="$ROOT_DIR/AgentRuntime/sci_station_agent"
SOURCE_LAUNCHER="$ROOT_DIR/AgentRuntime/sci_station_sidecar.py"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-runtime.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Sidecar staging requires a built Sci-Station app: $APP_PATH" >&2
  exit 1
fi
if [[ ! -d "$SOURCE_PACKAGE" || ! -f "$SOURCE_LAUNCHER" ]]; then
  echo "Sidecar source package is incomplete under $ROOT_DIR/AgentRuntime." >&2
  exit 1
fi

verify_archive() {
  local archive_path="$1"
  local actual_sha256

  [[ -f "$archive_path" ]] || return 1
  actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  [[ "$actual_sha256" == "$RUNTIME_ARCHIVE_SHA256" ]]
}

if ! verify_archive "$RUNTIME_ARCHIVE"; then
  if [[ -n "${SCI_STATION_RUNTIME_ARCHIVE:-}" ]]; then
    echo "SCI_STATION_RUNTIME_ARCHIVE failed SHA-256 verification: $RUNTIME_ARCHIVE" >&2
    exit 1
  fi

  mkdir -p "$RUNTIME_CACHE_DIR"
  DOWNLOAD_PATH="$TEMP_ROOT/$RUNTIME_ARCHIVE_NAME"
  echo "==> Downloading pinned Python $PYTHON_VERSION sidecar runtime..."
  curl \
    --fail \
    --location \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 20 \
    --output "$DOWNLOAD_PATH" \
    "$RUNTIME_ARCHIVE_URL"
  if ! verify_archive "$DOWNLOAD_PATH"; then
    echo "Downloaded sidecar runtime failed SHA-256 verification." >&2
    exit 1
  fi
  /usr/bin/ditto "$DOWNLOAD_PATH" "$RUNTIME_CACHE_DIR/$RUNTIME_ARCHIVE_NAME"
  RUNTIME_ARCHIVE="$RUNTIME_CACHE_DIR/$RUNTIME_ARCHIVE_NAME"
fi

echo "==> Staging verified Python sidecar runtime..."
EXTRACTED_ROOT="$TEMP_ROOT/extracted"
mkdir -p "$EXTRACTED_ROOT"
tar -xzf "$RUNTIME_ARCHIVE" -C "$EXTRACTED_ROOT"
if [[ ! -x "$EXTRACTED_ROOT/python/bin/python3" ]]; then
  echo "The verified runtime archive does not contain python/bin/python3." >&2
  exit 1
fi

rm -rf "$RUNTIME_DESTINATION" "$SIDECAR_DESTINATION"
mkdir -p "$RESOURCES_DIR" "$SIDECAR_DESTINATION"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr "$EXTRACTED_ROOT/python" "$RUNTIME_DESTINATION"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr "$SOURCE_PACKAGE" "$SIDECAR_DESTINATION/sci_station_agent"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr "$SOURCE_LAUNCHER" "$SIDECAR_DESTINATION/sci_station_sidecar.py"

# The sidecar needs only the standard-library runtime. Remove installers,
# development headers, GUI tooling, and Tcl/Tk so the production helper cannot
# mutate itself or expose unrelated executable surfaces.
find "$RUNTIME_DESTINATION/bin" -mindepth 1 -maxdepth 1 ! -name python3.12 -delete
ln -s python3.12 "$RUNTIME_DESTINATION/bin/python3"
ln -s python3.12 "$RUNTIME_DESTINATION/bin/python"
rm -rf \
  "$RUNTIME_DESTINATION/include" \
  "$RUNTIME_DESTINATION/share" \
  "$RUNTIME_DESTINATION/lib/itcl4.3.5" \
  "$RUNTIME_DESTINATION/lib/pkgconfig" \
  "$RUNTIME_DESTINATION/lib/tcl9" \
  "$RUNTIME_DESTINATION/lib/tcl9.0" \
  "$RUNTIME_DESTINATION/lib/thread3.0.4" \
  "$RUNTIME_DESTINATION/lib/tk9.0" \
  "$RUNTIME_DESTINATION/lib/python3.12/config-3.12-darwin" \
  "$RUNTIME_DESTINATION/lib/python3.12/ensurepip" \
  "$RUNTIME_DESTINATION/lib/python3.12/idlelib" \
  "$RUNTIME_DESTINATION/lib/python3.12/lib2to3" \
  "$RUNTIME_DESTINATION/lib/python3.12/site-packages" \
  "$RUNTIME_DESTINATION/lib/python3.12/tkinter" \
  "$RUNTIME_DESTINATION/lib/python3.12/turtledemo"
rm -f \
  "$RUNTIME_DESTINATION/lib/libtcl9.0.dylib" \
  "$RUNTIME_DESTINATION/lib/libtcl9tk9.0.dylib" \
  "$RUNTIME_DESTINATION/lib/python3.12/lib-dynload/_tkinter.cpython-312-darwin.so"

find "$RUNTIME_DESTINATION" "$SIDECAR_DESTINATION" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$RUNTIME_DESTINATION" "$SIDECAR_DESTINATION" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
rm -rf "$SIDECAR_DESTINATION/sci_station_agent/uitest"
chmod 755 "$RUNTIME_DESTINATION/bin/python3.12"
chmod 644 "$SIDECAR_DESTINATION/sci_station_sidecar.py"
find "$RUNTIME_DESTINATION/lib/python3.12" "$SIDECAR_DESTINATION" -type f -name '*.py' -exec chmod 644 {} +

cat >"$SIDECAR_DESTINATION/runtime-manifest.json" <<EOF
{
  "architecture": "arm64",
  "archiveSHA256": "$RUNTIME_ARCHIVE_SHA256",
  "distribution": "astral-sh/python-build-standalone",
  "pythonVersion": "$PYTHON_VERSION",
  "release": "$RUNTIME_RELEASE",
  "sidecarVersion": "0.1.0"
}
EOF

RUNTIME_ARCHITECTURES="$(lipo -archs "$RUNTIME_DESTINATION/bin/python3.12")"
case " $RUNTIME_ARCHITECTURES " in
  *" arm64 "*) ;;
  *)
    echo "Bundled sidecar runtime is missing arm64: $RUNTIME_ARCHITECTURES" >&2
    exit 1
    ;;
esac

RUNTIME_VERSION="$($RUNTIME_DESTINATION/bin/python3 -I -c 'import platform; print(platform.python_version())')"
if [[ "$RUNTIME_VERSION" != "$PYTHON_VERSION" ]]; then
  echo "Unexpected staged Python version: $RUNTIME_VERSION" >&2
  exit 1
fi

echo "Pinned sidecar runtime staged: Python $PYTHON_VERSION ($RUNTIME_RELEASE, arm64)"
