#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
RUNTIME_ROOT="$APP_PATH/Contents/Resources/SidecarRuntime"
PYTHON_EXECUTABLE="$RUNTIME_ROOT/bin/python3"
SIDECAR_ROOT="$APP_PATH/Contents/Resources/AgentRuntime"
LAUNCHER="$SIDECAR_ROOT/sci_station_sidecar.py"
MANIFEST="$SIDECAR_ROOT/runtime-manifest.json"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-sidecar-smoke.XXXXXX")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"
OPEN_PID=""
PREEXISTING_APP_PIDS=""

matching_app_pids() {
  while read -r pid command; do
    if [[ "$command" == "$APP_EXECUTABLE" || "$command" == "$APP_EXECUTABLE "* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -axo pid=,command=)
}

has_launched_app() {
  local pid

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case " $PREEXISTING_APP_PIDS " in
      *" $pid "*) ;;
      *) return 0 ;;
    esac
  done < <(matching_app_pids)
  return 1
}

terminate_launched_app() {
  local pid

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case " $PREEXISTING_APP_PIDS " in
      *" $pid "*) continue ;;
    esac
    kill -TERM "$pid" 2>/dev/null || true
  done < <(matching_app_pids)

  for _ in {1..25}; do
    if ! has_launched_app; then
      return
    fi
    sleep 0.2
  done

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case " $PREEXISTING_APP_PIDS " in
      *" $pid "*) continue ;;
    esac
    kill -KILL "$pid" 2>/dev/null || true
  done < <(matching_app_pids)
}

cleanup() {
  terminate_launched_app
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" 2>/dev/null; then
    kill -TERM "$OPEN_PID" 2>/dev/null || true
    wait "$OPEN_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

if [[ ! -x "$APP_EXECUTABLE" || ! -x "$PYTHON_EXECUTABLE" || ! -f "$LAUNCHER" || ! -f "$MANIFEST" ]]; then
  echo "The app does not contain a complete bundled sidecar runtime." >&2
  exit 1
fi

mkdir -p "$TEMP_ROOT/home" "$TEMP_ROOT/tmp" "$TEMP_ROOT/workspace"
OUTPUT_PATH="$TEMP_ROOT/app.log"
ERROR_PATH="$TEMP_ROOT/error.log"
touch "$OUTPUT_PATH" "$ERROR_PATH"

MANIFEST_PYTHON_VERSION="$(/usr/bin/plutil -extract pythonVersion raw "$MANIFEST")"
MANIFEST_SHA256="$(/usr/bin/plutil -extract archiveSHA256 raw "$MANIFEST")"
if [[ "$MANIFEST_PYTHON_VERSION" != "3.12.13" || "$MANIFEST_SHA256" != "9a1e9e06175c10efd8378b904b07fa21bd791ab3345d7cdffeb4a76c9ff55903" ]]; then
  echo "Bundled sidecar runtime manifest does not match the pinned release." >&2
  exit 1
fi

PREEXISTING_APP_PIDS="$(matching_app_pids | tr '\n' ' ')"
/usr/bin/open \
  -n \
  -W \
  -g \
  -o "$OUTPUT_PATH" \
  --stderr "$ERROR_PATH" \
  --env "HOME=$TEMP_ROOT/home" \
  --env "TMPDIR=$TEMP_ROOT/tmp" \
  --env "PATH=/usr/bin:/bin" \
  "$APP_PATH" \
  --args --sidecar-runtime-smoke-test &
OPEN_PID=$!

OPEN_EXIT_STATUS=""
for _ in {1..120}; do
  if ! kill -0 "$OPEN_PID" 2>/dev/null; then
    set +e
    wait "$OPEN_PID"
    OPEN_EXIT_STATUS=$?
    set -e
    OPEN_PID=""
    break
  fi
  sleep 0.25
done

if [[ -n "$OPEN_PID" ]]; then
  echo "App-integrated sidecar smoke test timed out." >&2
  sed -n '1,160p' "$OUTPUT_PATH" >&2
  sed -n '1,160p' "$ERROR_PATH" >&2
  exit 1
fi
if [[ "$OPEN_EXIT_STATUS" != "0" ]] || ! grep -q '^SCI_STATION_SIDECAR_SMOKE_OK status=ready python=3.12.13 isolated=1$' "$OUTPUT_PATH"; then
  echo "App-integrated sidecar smoke test failed through LaunchServices with status ${OPEN_EXIT_STATUS:-unknown}." >&2
  sed -n '1,160p' "$OUTPUT_PATH" >&2
  sed -n '1,160p' "$ERROR_PATH" >&2
  exit 1
fi

echo "Bundled Python sidecar handshake passed through the sandboxed app and LaunchServices."
