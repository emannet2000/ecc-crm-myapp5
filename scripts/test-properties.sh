#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../golang-backend"
for target in FuzzPhoneNormalization FuzzCurrencyValidation FuzzCSVFormulaNeutralization FuzzRecordVersionProperties FuzzMoneyRounding; do
  go test -run '^$' -fuzz "^${target}$" -fuzztime="${ECC_FUZZ_TIME:-5s}" -parallel=2 -timeout=90s
done
