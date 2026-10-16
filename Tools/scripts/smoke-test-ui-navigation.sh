#!/usr/bin/env bash
# Exercise the exact app bundle through Xcode's native macOS UI test runner.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Sci-Station.app" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "UI smoke test could not find Info.plist at $INFO_PLIST" >&2
  exit 1
fi
APP_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
if [[ ! -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME" ]]; then
  echo "UI smoke test found no executable app binary in $APP_PATH" >&2
  exit 1
fi

# Keep the runner outside the app and reuse its incremental build across the
# release, installation, and overwrite-upgrade checks. The target has no app
# dependency, so these checks cannot silently rebuild the artifact under test.
RUNNER_BUILD_DIR="$ROOT_DIR/.tmp/ui-smoke-runner"
RESULTS_DIR="$ROOT_DIR/.tmp/ui-smoke-results"
mkdir -p "$RESULTS_DIR"
RUN_ROOT="$(mktemp -d "$RESULTS_DIR/run.XXXXXX")"
PROFILE_PATH="$RUN_ROOT/profile"
mkdir -p "$PROFILE_PATH/home" "$PROFILE_PATH/tmp"
OPEN_PID=""
APP_PID=""
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"

matching_app_pids() {
  while read -r pid command; do
    if [[ "$command" == "$APP_EXECUTABLE" || "$command" == "$APP_EXECUTABLE "* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -axo pid=,command=)
}

cleanup() {
  # Only terminate the precise instance launched by this invocation.
  if [[ -n "$APP_PID" ]] && matching_app_pids | grep -Fxq "$APP_PID"; then
    kill -TERM "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" 2>/dev/null; then
    kill -TERM "$OPEN_PID" 2>/dev/null || true
    wait "$OPEN_PID" 2>/dev/null || true
  fi
  rm -rf "$PROFILE_PATH"
}
trap cleanup EXIT

if [[ -n "$(matching_app_pids)" ]]; then
  echo "The exact app bundle is already running. Close that instance before its UI smoke test." >&2
  exit 1
fi

echo "==> Building the macOS UI test runner..."
if ! xcodebuild \
  -project "$ROOT_DIR/Sci-Station.xcodeproj" \
  -scheme Sci-Station-UI-Smoke \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$RUNNER_BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build-for-testing >"$RUN_ROOT/build.log" 2>&1; then
  tail -n 100 "$RUN_ROOT/build.log" >&2
  echo "UI runner build failed. Diagnostics: $RUN_ROOT" >&2
  exit 1
fi

# Launch outside the sandboxed XCTest runner: NSWorkspace intentionally ignores
# command-line arguments from sandboxed callers. -n keeps any other installed
# copy with the same bundle identifier untouched.
/usr/bin/open \
  -n -W \
  -o "$RUN_ROOT/app.log" \
  --stderr "$RUN_ROOT/app-error.log" \
  --env "HOME=$PROFILE_PATH/home" \
  --env "TMPDIR=$PROFILE_PATH/tmp" \
  --env "PATH=/usr/bin:/bin" \
  --env "SCI_STATION_UI_TEST_HOST=1" \
  "$APP_PATH" --args --ui-test-host &
OPEN_PID=$!

HOST_READY=0
for _ in {1..200}; do
  APP_PID="$(matching_app_pids | head -n 1)"
  if [[ -n "$APP_PID" ]] && grep -Fxq 'SCI_STATION_UI_TEST_HOST_READY' "$RUN_ROOT/app.log" 2>/dev/null; then
    HOST_READY=1
    break
  fi
  sleep 0.1
done
if [[ "$HOST_READY" != "1" ]]; then
  echo "The exact app did not enter its isolated UI test initial state. Diagnostics: $RUN_ROOT" >&2
  tail -n 60 "$RUN_ROOT/app.log" "$RUN_ROOT/app-error.log" >&2
  exit 1
fi

# Pass the verified artifact path and process to the test process. Preserve
# __TESTROOT__ when moving Xcode's generated run specification.
python3 - "$RUNNER_BUILD_DIR/Build/Products" "$RUN_ROOT/TestRun.xctestrun" "$APP_PATH" "$APP_PID" <<'PY'
import plistlib
import sys
from pathlib import Path

products, destination, app_path, app_pid = sys.argv[1:]
run_files = list(Path(products).glob("Sci-Station-UI-Smoke_*.xctestrun"))
if not run_files:
    raise SystemExit("Xcode did not generate the UI smoke run specification.")
source = max(run_files, key=lambda path: path.stat().st_mtime)
with source.open("rb") as stream:
    specification = plistlib.load(stream)
target_count = 0

def configure(value):
    global target_count
    if isinstance(value, dict):
        if "TestBundlePath" in value:
            environment = value.setdefault("EnvironmentVariables", {})
            environment["SCI_STATION_UI_TEST_APP_PATH"] = app_path
            environment["SCI_STATION_UI_TEST_APP_PID"] = app_pid
            target_count += 1
        return {key: configure(item) for key, item in value.items()}
    if isinstance(value, list):
        return [configure(item) for item in value]
    if isinstance(value, str):
        return value.replace("__TESTROOT__", str(source.parent))
    return value

specification = configure(specification)
if target_count != 1:
    raise SystemExit(f"Expected one UI smoke test target, found {target_count}.")
with Path(destination).open("wb") as stream:
    plistlib.dump(specification, stream)
PY

echo "==> Clicking Library in the supplied app bundle..."
if ! xcodebuild \
  -xctestrun "$RUN_ROOT/TestRun.xctestrun" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RUN_ROOT/Navigation.xcresult" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 \
  test-without-building >"$RUN_ROOT/test.log" 2>&1; then
  tail -n 120 "$RUN_ROOT/test.log" >&2
  echo "Native UI navigation failed. Review $RUN_ROOT/Navigation.xcresult and $RUN_ROOT/test.log." >&2
  echo "If Xcode requests UI automation authorization, grant it through the normal macOS prompt before rerunning this gate." >&2
  exit 1
fi

echo "Sci-Station passed native UI navigation: visible Home, real Library click, visible Library destination."
echo "UI test result: $RUN_ROOT/Navigation.xcresult"
