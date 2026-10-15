#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
coverage_dir="$project_root/tests/artifacts/coverage"
mkdir -p "$coverage_dir"
cd golang-backend
# Keep subprocesses on the same compiler when the host Go version is older.
if [[ -z "${GOTOOLCHAIN:-}" || "${GOTOOLCHAIN:-}" == "auto" ]]; then
  coverage_go_version="$(awk '$1 == "go" { print $2; exit }' go.mod)"
  export GOTOOLCHAIN="go${coverage_go_version}"
fi
go test -coverprofile="$coverage_dir/backend.cover" ./... -timeout=180s
go tool cover -func="$coverage_dir/backend.cover" > "$coverage_dir/backend-functions.txt"
python3 "$project_root/scripts/report-function-coverage.py" "$coverage_dir/backend-functions.txt" "$coverage_dir/backend-functions.md"
