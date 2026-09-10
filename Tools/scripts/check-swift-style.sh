#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

swiftlint_bin="${SWIFTLINT_BIN:-swiftlint}"
swiftformat_bin="${SWIFTFORMAT_BIN:-swiftformat}"
expected_swiftlint_version="0.65.0"
expected_swiftformat_version="0.62.1"

if ! command -v "$swiftlint_bin" >/dev/null 2>&1; then
  echo "SwiftLint is required. Install the pinned tools with: brew install mint && mint bootstrap" >&2
  exit 1
fi

if ! command -v "$swiftformat_bin" >/dev/null 2>&1; then
  echo "SwiftFormat is required. Install the pinned tools with: brew install mint && mint bootstrap" >&2
  exit 1
fi

actual_swiftlint_version="$($swiftlint_bin version)"
actual_swiftformat_version="$($swiftformat_bin --version)"

if [[ "$actual_swiftlint_version" != "$expected_swiftlint_version" ]]; then
  echo "SwiftLint $expected_swiftlint_version is required; found $actual_swiftlint_version." >&2
  exit 1
fi

if [[ "$actual_swiftformat_version" != "$expected_swiftformat_version" ]]; then
  echo "SwiftFormat $expected_swiftformat_version is required; found $actual_swiftformat_version." >&2
  exit 1
fi

runtime_baseline="$(mktemp "${TMPDIR:-/tmp}/sci-station-swiftlint-baseline.XXXXXX")"
trap 'rm -f "$runtime_baseline"' EXIT
SCI_STATION_ROOT="$repo_root" /usr/bin/ruby -rjson -e '
  source_path, output_path = ARGV
  marker = "file://__SCI_STATION_ROOT__"
  replacement = "file://#{ENV.fetch("SCI_STATION_ROOT")}"
  baseline = JSON.parse(File.read(source_path))
  baseline.each do |entry|
    location = entry.dig("violation", "location")
    file = location&.fetch("file", nil)
    abort "SwiftLint baseline contains a non-portable path: #{file.inspect}" unless file&.start_with?("#{marker}/")
    location["file"] = file.sub(marker, replacement)
  end
  File.write(output_path, JSON.generate(baseline))
' .swiftlint-baseline.json "$runtime_baseline"

echo "Running SwiftLint $actual_swiftlint_version..."
"$swiftlint_bin" lint \
  --config .swiftlint.yml \
  --baseline "$runtime_baseline" \
  --strict \
  --no-cache \
  --quiet

echo "Running SwiftFormat $actual_swiftformat_version in lint mode..."
"$swiftformat_bin" \
  Sci-Station \
  Tests \
  Tools \
  Package.swift \
  --config .swiftformat \
  --cache ignore \
  --lint
