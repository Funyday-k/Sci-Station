#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="${APP_OUTPUT:-$root_dir/build/Sci-Station.app}"
mode="${1:-run}"
case "$mode" in
    run|debug|--debug|logs|--logs|telemetry|--telemetry|verify|--verify) ;;
    *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
make -C "$root_dir" app APP_OUTPUT="$bundle"
case "$mode" in
    debug|--debug) exec lldb -- "$bundle/Contents/MacOS/sci-station" ;;
    verify|--verify) make -C "$root_dir" verify APP_OUTPUT="$bundle" ;;
esac
/usr/bin/open "$bundle"
case "$mode" in
    logs|--logs|telemetry|--telemetry)
        exec /usr/bin/log stream --info --style compact --predicate 'process == "sci-station"'
        ;;
esac
