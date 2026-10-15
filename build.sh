#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")"
elm make src/Main.elm --output=elm.js --optimize
elm make src/Account.elm --output=public/account-elm.js --optimize
elm make src/RecordBrowser.elm --output=public/record-browser-elm.js --optimize
elm make src/WorkDashboard.elm --output=public/work-dashboard-elm.js --optimize
mkdir -p build
(cd golang-backend && go build -o ../build/ecc-crm .)
echo "Build complete. Start the app with ./build/ecc-crm"
