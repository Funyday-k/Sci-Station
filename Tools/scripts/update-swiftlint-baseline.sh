#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

swiftlint_bin="${SWIFTLINT_BIN:-swiftlint}"
expected_version="0.65.0"

if ! command -v "$swiftlint_bin" >/dev/null 2>&1; then
  echo "SwiftLint is required. Install the pinned tools with: brew install mint && mint bootstrap" >&2
  exit 1
fi

actual_version="$($swiftlint_bin version)"
if [[ "$actual_version" != "$expected_version" ]]; then
  echo "SwiftLint $expected_version is required; found $actual_version." >&2
  exit 1
fi

"$swiftlint_bin" lint \
  --config .swiftlint.yml \
  --write-baseline .swiftlint-baseline.json \
  --lenient \
  --no-cache \
  --quiet

SCI_STATION_ROOT="$repo_root" /usr/bin/ruby -rjson -e '
  path = ARGV.fetch(0)
  root = "file://#{ENV.fetch("SCI_STATION_ROOT")}"
  marker = "file://__SCI_STATION_ROOT__"
  baseline = JSON.parse(File.read(path))
  baseline.each do |entry|
    location = entry.dig("violation", "location")
    file = location&.fetch("file", nil)
    abort "Unexpected SwiftLint baseline path: #{file.inspect}" unless file&.start_with?("#{root}/")
    location["file"] = file.sub(root, marker)
  end
  File.write(path, JSON.generate(baseline) + "\n")
' .swiftlint-baseline.json

echo "Updated portable SwiftLint baseline with the existing violations."
