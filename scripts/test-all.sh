#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Coverage invokes compiler subprocesses; keep them on the module's toolchain.
if [[ -z "${GOTOOLCHAIN:-}" || "${GOTOOLCHAIN:-}" == "auto" ]]; then
  verification_go_version="$(awk '$1 == "go" { print $2; exit }' golang-backend/go.mod)"
  export GOTOOLCHAIN="go${verification_go_version}"
fi
./build.sh
mkdir -p tests/artifacts/coverage
(
  cd golang-backend
  go test -race -timeout 10m -coverprofile=../tests/artifacts/coverage/backend.cover ./...
  go vet ./...
  go tool cover -func=../tests/artifacts/coverage/backend.cover > ../tests/artifacts/coverage/backend-functions.txt
)
python3 scripts/report-function-coverage.py tests/artifacts/coverage/backend-functions.txt tests/artifacts/coverage/backend-functions.md
./scripts/test-properties.sh
python3 -m unittest discover -s tests -p '*_test.py'
npm test
# Run browser files sequentially: fixtures use isolated databases, while some
# still reserve fixed ports and Chromium is expensive under concurrent load.
ECC_BROWSER_LIVE=true node --test --test-concurrency=1 \
  tests/browser.test.cjs tests/journey.browser.cjs \
  tests/improvements.browser.cjs tests/reports.browser.cjs \
  tests/administration.browser.cjs tests/mobile-chat.browser.cjs \
  tests/workspace-next.browser.cjs tests/consolidation.browser.cjs \
  tests/workflow.browser.cjs tests/offline.browser.cjs
