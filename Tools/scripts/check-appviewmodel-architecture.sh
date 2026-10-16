#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
app_dir="$repo_root/Sci-Station/App"
main_file="$app_dir/AppViewModel.swift"
store_file="$repo_root/Sci-Station/Workspace/AppDomainStores.swift"

main_max_lines="${SCI_STATION_APPVIEWMODEL_MAIN_MAX_LINES:-1200}"
extension_max_lines="${SCI_STATION_APPVIEWMODEL_EXTENSION_MAX_LINES:-1800}"
family_max_lines="${SCI_STATION_APPVIEWMODEL_FAMILY_MAX_LINES:-11000}"
published_max="${SCI_STATION_APPVIEWMODEL_PUBLISHED_MAX:-135}"
minimum_extension_files="${SCI_STATION_APPVIEWMODEL_MIN_EXTENSION_FILES:-8}"

require_non_negative_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "error: $name must be a non-negative integer, got '$value'" >&2
    exit 2
  fi
}

line_count() {
  wc -l <"$1" | tr -d '[:space:]'
}

require_non_negative_integer SCI_STATION_APPVIEWMODEL_MAIN_MAX_LINES "$main_max_lines"
require_non_negative_integer SCI_STATION_APPVIEWMODEL_EXTENSION_MAX_LINES "$extension_max_lines"
require_non_negative_integer SCI_STATION_APPVIEWMODEL_FAMILY_MAX_LINES "$family_max_lines"
require_non_negative_integer SCI_STATION_APPVIEWMODEL_PUBLISHED_MAX "$published_max"
require_non_negative_integer SCI_STATION_APPVIEWMODEL_MIN_EXTENSION_FILES "$minimum_extension_files"

if [[ ! -f "$main_file" ]]; then
  echo "error: AppViewModel entry point not found: $main_file" >&2
  exit 2
fi

if [[ ! -f "$store_file" ]]; then
  echo "error: focused domain store file not found: $store_file" >&2
  exit 2
fi

shopt -s nullglob
extension_files=("$app_dir"/AppViewModel+*.swift)
shopt -u nullglob

failure_count=0
main_lines="$(line_count "$main_file")"
family_lines="$main_lines"

printf 'AppViewModel architecture budget:\n'
printf '  %-52s %5s / %5s lines\n' "Sci-Station/App/AppViewModel.swift" "$main_lines" "$main_max_lines"
if (( main_lines > main_max_lines )); then
  echo "error: AppViewModel.swift exceeds its line budget; move state or behavior into a focused store/use case" >&2
  failure_count=$((failure_count + 1))
fi

for file in "${extension_files[@]}"; do
  lines="$(line_count "$file")"
  family_lines=$((family_lines + lines))
  relative_path="${file#"$repo_root/"}"
  printf '  %-52s %5s / %5s lines\n' "$relative_path" "$lines" "$extension_max_lines"
  if (( lines > extension_max_lines )); then
    echo "error: $relative_path exceeds the per-extension line budget" >&2
    failure_count=$((failure_count + 1))
  fi
done

extension_count="${#extension_files[@]}"
printf '  %-52s %5s / %5s minimum\n' "AppViewModel extension files" "$extension_count" "$minimum_extension_files"
if (( extension_count < minimum_extension_files )); then
  echo "error: AppViewModel responsibilities have collapsed back into too few extension files" >&2
  failure_count=$((failure_count + 1))
fi

printf '  %-52s %5s / %5s lines\n' "AppViewModel family total" "$family_lines" "$family_max_lines"
if (( family_lines > family_max_lines )); then
  echo "error: AppViewModel family exceeds its total line budget; add Core use cases instead of growing the facade" >&2
  failure_count=$((failure_count + 1))
fi

published_count="$(grep -Ec '^[[:space:]]*@Published([[:space:]]|$)' "$main_file" || true)"
printf '  %-52s %5s / %5s properties\n' "AppViewModel @Published state" "$published_count" "$published_max"
if (( published_count > published_max )); then
  echo "error: AppViewModel adds app-wide published state beyond the budget; place domain state in a focused store" >&2
  failure_count=$((failure_count + 1))
fi

required_stores=(
  WorkspaceStore
  LibraryStore
  KnowledgeStore
  RecommendationStore
  AgentStore
  NavigationStore
)

for store_type in "${required_stores[@]}"; do
  if ! grep -Fq "final class $store_type: ObservableObject" "$store_file"; then
    echo "error: missing focused store declaration: $store_type" >&2
    failure_count=$((failure_count + 1))
  fi
done

if (( failure_count > 0 )); then
  echo "AppViewModel architecture budget failed with $failure_count violation(s)." >&2
  exit 1
fi

echo "AppViewModel architecture budget passed."
