#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-ui-smoke.XXXXXX")"
OPEN_PID=""
PREEXISTING_APP_PIDS=""

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "UI smoke test could not find Info.plist at $INFO_PLIST" >&2
  exit 1
fi

APP_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"
OUTPUT_PATH="$TEMP_ROOT/app.log"
ERROR_PATH="$TEMP_ROOT/error.log"

matching_app_pids() {
  while read -r pid command; do
    if [[ "$command" == "$APP_EXECUTABLE" || "$command" == "$APP_EXECUTABLE "* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -axo pid=,command=)
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

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "UI smoke test found no executable app binary at $APP_EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$TEMP_ROOT/home" "$TEMP_ROOT/tmp"
touch "$OUTPUT_PATH" "$ERROR_PATH"
PREEXISTING_APP_PIDS="$(matching_app_pids | tr '\n' ' ')"

# This is an interaction smoke test, not a background-launch test. Keep the
# application foreground-capable so AppKit/SwiftUI materializes the same
# accessibility hierarchy and press actions that a real user sees.
/usr/bin/open \
  -n \
  -W \
  -o "$OUTPUT_PATH" \
  --stderr "$ERROR_PATH" \
  --env "HOME=$TEMP_ROOT/home" \
  --env "TMPDIR=$TEMP_ROOT/tmp" \
  --env "PATH=/usr/bin:/bin" \
  --env "SCI_STATION_UI_SMOKE_TEST=1" \
  "$APP_PATH" \
  --args --app-ui-smoke-test &
OPEN_PID=$!

OPEN_EXIT_STATUS=""
for _ in {1..160}; do
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
  echo "App-integrated UI navigation smoke test timed out." >&2
  sed -n '1,200p' "$OUTPUT_PATH" >&2
  sed -n '1,200p' "$ERROR_PATH" >&2
  exit 1
fi

success_pattern='^SCI_STATION_UI_SMOKE_OK root=app\.main_window\.root action=sidebar\.tab\.library destination=workspace\.section\.library window=[0-9]+x[0-9]+$'
if [[ "$OPEN_EXIT_STATUS" != "0" ]] || ! grep -Eq "$success_pattern" "$OUTPUT_PATH"; then
  echo "App-integrated UI navigation smoke test failed through LaunchServices with status ${OPEN_EXIT_STATUS:-unknown}." >&2
  sed -n '1,200p' "$OUTPUT_PATH" >&2
  sed -n '1,200p' "$ERROR_PATH" >&2
  exit 1
fi

echo "Sci-Station rendered its main window and completed accessibility-driven Library navigation."
