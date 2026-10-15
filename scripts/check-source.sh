#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mapfile -d '' go_sources < <(git ls-files -z '*.go')
unformatted="$(gofmt -l "${go_sources[@]}")"
if [[ -n "$unformatted" ]]; then
  printf 'Run gofmt on these files:\n%s\n' "$unformatted" >&2
  exit 1
fi

while IFS= read -r -d '' source; do
  node --check "$source"
done < <(git ls-files -z '*.js' '*.cjs' '*.mjs')

while IFS= read -r -d '' source; do
  bash -n "$source"
done < <(git ls-files -z '*.sh')
