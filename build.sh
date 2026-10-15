#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")"
elm_compiler="./node_modules/.bin/elm"
if [[ ! -x "$elm_compiler" ]]; then
  elm_compiler="elm"
fi
if [[ "$("$elm_compiler" --version)" != "0.19.2" ]]; then
  echo "Elm 0.19.2 is required. Run npm install to install the project compiler." >&2
  exit 1
fi
"$elm_compiler" make src/Main.elm --output=elm.js --optimize
"$elm_compiler" make src/Account.elm --output=public/account-elm.js --optimize
"$elm_compiler" make src/RecordBrowser.elm --output=public/record-browser-elm.js --optimize
"$elm_compiler" make src/WorkDashboard.elm --output=public/work-dashboard-elm.js --optimize
mkdir -p build
(cd golang-backend && go build -o ../build/ecc-crm .)
echo "Build complete. Start the app with ./build/ecc-crm"
