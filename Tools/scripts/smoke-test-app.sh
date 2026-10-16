#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_BUNDLE="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
WINDOW_PROBE="$ROOT_DIR/Tools/scripts/ui-window-probe.swift"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "App smoke test could not find Info.plist at $INFO_PLIST" >&2
  exit 1
fi

BUNDLE_TYPE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [[ "$BUNDLE_TYPE" != "APPL" || ! -x "$APP_BINARY" || ! -f "$WINDOW_PROBE" ]]; then
  echo "App smoke test found an incomplete bundle or UI probe at $APP_BUNDLE" >&2
  exit 1
fi

PROFILE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sci-station-ui-smoke.XXXXXX")"
OUTPUT_PATH="$PROFILE_DIR/app.log"
ERROR_PATH="$PROFILE_DIR/error.log"
PROBE_OUTPUT="$PROFILE_DIR/window-probe.log"
OPEN_PID=""
APP_PID=""
PREEXISTING_APP_PIDS=""
mkdir -p "$PROFILE_DIR/home" "$PROFILE_DIR/tmp"
touch "$OUTPUT_PATH" "$ERROR_PATH"

matching_app_pids() {
  while read -r pid command; do
    if [[ "$command" == "$APP_BINARY" || "$command" == "$APP_BINARY "* ]]; then
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

find_launched_app_pid() {
  local pid

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case " $PREEXISTING_APP_PIDS " in
      *" $pid "*) continue ;;
    esac
    printf '%s\n' "$pid"
    return 0
  done < <(matching_app_pids)
  return 1
}

terminate_app() {
  local pid

  if [[ -n "$APP_PID" ]]; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  fi
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
  terminate_app
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" 2>/dev/null; then
    kill -TERM "$OPEN_PID" 2>/dev/null || true
    wait "$OPEN_PID" 2>/dev/null || true
  fi
  rm -rf "$PROFILE_DIR"
}
trap cleanup EXIT

PREEXISTING_APP_PIDS="$(matching_app_pids | tr '\n' ' ')"
/usr/bin/open \
  -n \
  -W \
  -F \
  -g \
  -o "$OUTPUT_PATH" \
  --stderr "$ERROR_PATH" \
  --env "HOME=$PROFILE_DIR/home" \
  --env "TMPDIR=$PROFILE_DIR/tmp" \
  --env "PATH=/usr/bin:/bin" \
  "$APP_BUNDLE" &
OPEN_PID=$!

for _ in {1..80}; do
  if APP_PID="$(find_launched_app_pid)"; then
    break
  fi
  if ! kill -0 "$OPEN_PID" 2>/dev/null; then
    echo "LaunchServices returned before Sci-Station started." >&2
    sed -n '1,200p' "$OUTPUT_PATH" >&2
    sed -n '1,200p' "$ERROR_PATH" >&2
    exit 1
  fi
  sleep 0.25
done

if [[ -z "$APP_PID" ]]; then
  echo "Could not identify the Sci-Station process launched by LaunchServices." >&2
  exit 1
fi

if ! xcrun swift "$WINDOW_PROBE" "$APP_PID" 30 >"$PROBE_OUTPUT" 2>&1; then
  echo "Sci-Station failed the real main-window UI smoke test." >&2
  sed -n '1,200p' "$PROBE_OUTPUT" >&2
  sed -n '1,200p' "$OUTPUT_PATH" >&2
  sed -n '1,200p' "$ERROR_PATH" >&2
  exit 1
fi

terminate_app
APP_PID=""
if [[ -n "$OPEN_PID" ]]; then
  wait "$OPEN_PID" || OPEN_STATUS=$?
  OPEN_PID=""
  if [[ "${OPEN_STATUS:-0}" != "0" ]]; then
    echo "LaunchServices reported status $OPEN_STATUS after the UI smoke test." >&2
    exit 1
  fi
fi

cat "$PROBE_OUTPUT"
echo "Sci-Station displayed its main window through LaunchServices."
