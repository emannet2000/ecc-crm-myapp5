# Session and save acceptance — 2026-10-15

Scope: current local working tree based on commit `8f87110`, including existing
uncommitted session, request-order and save-order changes. This is local
verification, not acceptance of a deployed release.

## Fixes

- Administration Elm checks now prefer the installed project compiler, matching
  the build script. The system compiler was 0.19.1; this project requires 0.19.2.
  Compilation failures now include compiler diagnostics.
- The live offline contact test waits for Elm to enable Save before clicking and
  reports the modal and offline queue state if completion times out.

## Verification

| Check | Result |
| --- | --- |
| `./build.sh` | Passed: all four Elm entry points and Go binary built. |
| `npm test` | Passed: 40 tests, no failures or skips. |
| `ECC_BROWSER_LIVE=true node --test tests/browser.test.cjs tests/journey.browser.cjs` | Passed: 44 tests, no failures or skips. |
| `go vet ./...` | Passed. |
| `go test -race ./... -timeout 10m` | Passed outside the sandbox (469 seconds). Initial sandbox run could not open the SMTP fixture socket. |
| `ECC_BROWSER_LIVE=true node --test tests/offline.browser.cjs` | Passed: 5 tests, no failures or skips, including live contact save/reload/sync. |

Browser checks used isolated temporary databases with demo data. They cover
server/network session failures, delayed refresh after logout, logout retries,
same-account draft restoration, cross-tab account changes, delayed navigation
replies, rejected saves, edits made during pending saves, overlapping saves,
profile/deletion/bulk response ordering, and the education journey through
conversion, documents, finance, portal, roles and mobile layouts.

## Acceptance still required

**Live providers: pending.** No designated acceptance URL, login, dedicated contact,
recipient or unpaid test invoice was configured in this session. No external
messages or provider calls were made. Supply the test environment and configure
credentials privately, then run the strict runner and companion scenarios in
[Integration acceptance](INTEGRATION_ACCEPTANCE.md). Required scope defaults to
email, WhatsApp, Stripe test payments and AI. Record actual delivery/replies,
signed event replay, ledger/balance effects, and AI confirmation/access behavior.

**Staff: pending.** No actual adviser, finance or receiving-adviser observations
were supplied. Use [the staff session worksheet](STAFF_SESSION_WORKSHEET.md) with
normal staff accounts and harmless test records. Record completion, time, errors,
help and exact obstacles; fix and retest observed problems with the same role.
Automated browser results do not establish staff acceptance.

Deployment performance and deployed-environment verification also remain outside
this local acceptance record. Keep release acceptance open until required staff
and provider evidence is recorded.
