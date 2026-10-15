# Reliability audit — 2026-10-15

This audit combines source review, deterministic unit/regression checks, property tests, fuzzing, and isolated browser workflows. It does not establish that every function or every possible input is tested. Production provider acceptance, deployment performance and actual staff sessions remain separate work.

## Confirmed defects addressed

| Problem | What could go wrong | Change and evidence |
| --- | --- | --- |
| Recovery and invitation handlers ignored database errors | Password changes or invitation acceptance could report success while a required token-invalidation or security-audit write failed. A link could remain valid. | Six injected database-failure cases reproduced HTTP 200 before the fix. The handlers now return an error, causing account, token, session and mail changes to roll back. Regression and focused race tests pass. |
| SSO completion ignored token and audit errors | A sign-in could issue a session while token invalidation or its required audit write failed. | Token and audit errors now fail the request before session cookies are issued. Regression cases cover token, audit and session failures, preserved recovery codes, and successful single-use sign-in. |
| Record-browser replies mixed query state | A late request could append old rows after a new search or module switch. | The browser UI is now Elm, with captured queries and generation guards. Deliberately delayed search/module responses pass. |
| Currency matching used substring search | Combined strings such as `USD\|EUR` were accepted as a currency and could reach financial workflows. | Seeded property tests reproduced the defect. Exact supported-code matching now rejects combined strings; fuzzing passed. |
| Default installation created a public demo administrator | A fresh publicly reachable database started with a publicly documented privileged login. | New installations start empty. Demo seeding requires `SEED_DEMO_DATA=true`; unit tests cover unset, false and true settings, plus creation of the first real administrator. Existing accounts are not removed. |
| Administration discarded unsaved forms | Refresh, tab changes, managing another user, closing, navigation or sign-out could lose edits. | The screen now renders from Elm with Save, Discard and Stay. Failed saves retain the draft. Browser close/reload protection uses Elm state and a minimal browser port. |
| QR camera permission was blocked by the server | The browser could deny the camera despite the app offering QR scanning. | Permissions-Policy now permits same-origin camera access and continues denying microphone and geolocation. A header regression verifies this. Actual device camera acceptance remains unverified. |
| Removing navigation focus exposed a sixth mobile shortcut in a five-column layout | The mobile menu could wrap into a second row and cover content. | The fixed menu now uses six columns. Obsolete focus assertions and shadow-DOM selectors were updated in affected browser tests. |
| Offline tests simulated socket failures and could hang on timeout | Test durations exceeded their budget and failed cleanup could leave the browser runner hanging. | Offline regressions now use actual browser offline mode and register timeout cleanup. The two affected checks pass. This does not prove server-outage recovery for every latency pattern. |
| Malformed account response was treated as success | An HTTP 200 containing HTML, invalid JSON or an incomplete payload could clear the password and report success. | Elm now validates recovery confirmation messages and the SSO success status. Regression checks reject malformed responses and preserve entries. |
| CI and Docker used a different Elm compiler | Builds required Elm 0.19.2 but installed 0.19.1. | Both now pin the verified npm `elm@0.19.2-0` package, matching the locally installed compiler. Local builds pass; hosted CI and Docker execution remain unverified. |
| Standalone account Elm bundle was missing from the container build | Account recovery could work locally but load a missing asset in a clean image. | Dockerfile now compiles and copies the Account Elm bundle. Local app build passes; Docker image execution is not verified on this machine. |

## Remaining risks, in priority order

| Priority | Area | Failure scenario / evidence | Next work |
| --- | --- | --- | --- |
| High | Existing demo databases | Disabling future seeding does not revoke an already-created demo account. Existing production accounts were not inspected or changed. | The workspace owner should change credentials or disable the demo account before exposing a demo database. |
| High | Untested backend functions | Latest statement coverage is 57.3%; 294 of 922 measured functions are untouched. Some are wrappers or provider paths, but they are still explicit gaps. | Work through `FUNCTION_COVERAGE.md`, prioritizing authorization, finance, uploads, worker failures and data integrity. Coverage is not equivalent to assertion quality. |
| High | Real payments, email, WhatsApp and AI | Controlled tests cannot establish actual delivery, callback behavior, replay handling or provider billing in the deployment. | Use dedicated test providers and recipients with the strict acceptance runner. No actual provider messages or payments were initiated for this audit. |
| Medium | Remaining JavaScript frontend | Workspace forms, secondary reporting/Home summaries, record helpers, portal, offline UI and pickers still use handwritten JavaScript. They retain differing lifecycle and session-recovery policies. | Complete the requested Elm migration feature by feature, preserving workflows. Administration, Team chat, account recovery, primary management reports, the record browser and Home/work dashboard are migrated; full conversion is not complete. |
| Medium | Unchecked background writes | Delivery, notification and AI worker code still contains unchecked database results outside the recovery handlers fixed here. | Inject database failures around provider acceptance and persistence; verify retry, uncertain-result and duplicate-prevention behavior before modifying each worker. |
| Medium | Ambiguous network outcomes | A server may commit a create/send action before its response is lost. Retry behavior and idempotency are not uniform across all actions. | Test dropped responses after commit, especially teams, invitations, imports, messages and financial operations. Distinguish unknown outcomes from rejected changes. |
| Medium | Offline queue latency | The worker allows up to 100 jobs; fetches can wait 12 seconds, while the UI command timeout is 30 seconds. A large/slow sync can outlive its UI request. | Test large queues, slow networks, role revocation, storage quota failures, interrupted sync and browser termination. Retain drafts until server acceptance is confirmed. |
| Medium | Shared-network rate limits | General API and authentication limits are keyed by IP. Multiple staff behind one network share the limits. | Measure expected peak staff traffic and add multi-session/NAT load checks. |
| Medium | Backup and recovery in deployment | Four synthetic backup tests pass; this does not prove restoration of the deployment's own backup, paths, permissions or secrets. | Restore an actual deployment backup into an isolated environment and compare record counts and document hashes. |
| Medium | Date/time interpretation | Workspace timezone now offers city/zone suggestions and explains automatic daylight-saving rules. Security history still shows raw timestamps/event codes. | Add a current-time preview and readable history labels; test midnight, DST and date-only deadlines. |
| Medium | Browser/device differences | Chromium checks do not cover every mobile keyboard, camera, browser storage policy or accessibility combination. | Retest key staff tasks on the actual phones and browsers, including keyboard and screen-reader use. |
| Medium | Scale and availability | The repository has representative 5,000-record measurements; deployment latency, larger datasets, disk exhaustion and slow provider locks remain unverified. | Profile the deployment and test resource exhaustion with defined recovery expectations. |

## Test inventory and reproducible commands

- Full backend suite: passes after the fixes and startup regressions; statement coverage 57.3%.
- Frontend unit suite: 33 passing checks, including the Elm harness.
- Elm harness: 81 named regression checks and 2,000 deterministic generated navigation/date cases.
- Permission properties: 5,000 deterministic generated cases plus explicit same-workspace role/visibility/ownership boundaries.
- Backend fuzz targets: phone normalization, exact currency validation, CSV formula neutralization, record-version determinism and money rounding. All five timed fuzz runs passed.
- Unit tests directly exercise required-field validation for 12 record types, plus agent boundary checks.
- Recovery failure regression: six scenarios; focused race checks pass. SSO completion adds three database-failure cases plus successful single-use sign-in; all five cases, including rejection of a disabled account, pass.
- Backup / coverage-report / container-release scripts: eleven Python checks pass.
- Complete browser suite: 50 passing scenarios, zero failures or skips, including mobile/chat, offline/PWA upgrades, reporting, role checks and isolated backup restore.
- Consolidated communication, calendar, bulk selection, fixed navigation and directory browser scenario: passes.
- Offline account isolation/sign-out and live Elm contact offline reload/sync: pass. Two synthetic offline regressions pass after transport/cleanup corrections.
- Education journey: passes end to end, covering conversion, student/application work, review, finance, portal, roles and mobile. Obsolete navigation assertions and receipt-input readiness were corrected.
- New administration browser regression, covering actual DOM prompts, failed-save draft retention, access confirmation and browser reload protection: passes.
- A full race run hit its 180-second deadline during expensive fixture setup. It is not counted as a full race-suite pass. Focused new regression/property race checks pass.
- A QR decoder test exceeded its four-second decoder deadline during a concurrent heavy run, then passed in isolation. Timeout behavior is not treated as proof of a functional decoder defect.

Run `npm test`, `npm run test:elm`, `npm run test:properties`, `npm run test:coverage`, and `npm run test:administration`. Browser tests require Chromium/Puppeteer. Go/Elm compilation needs their package caches. Coverage scripts report every measured backend function, including untouched ones, and CI stores the reports as artifacts.

The full frontend migration and function-by-function test coverage are not complete. No zero-defect or zero-edge-case guarantee is made.

## Automatic test and release pipeline

`npm run test:all` builds all Elm entry points, collects backend race/coverage results, runs fuzzing, Python and frontend units, and runs browser regressions sequentially. GitHub Actions runs it on push, pull request, manual dispatch and a daily schedule. A tested container is published on successful main/version-tag pushes after its startup, assets and disabled demo-login checks pass. Workflow linting and four mocked container failure/cleanup regressions pass. See `CI_CD.md` for deployment prerequisites and the current target-selection status. Hosted CI and a Docker build have not been run here.

## Mobile regression improvements

The native Elm work queue now checks the viewport before its initial request,
using ten records on phones and twenty-five on larger screens. Screen resizing
preserves filters and resets pagination. Two Elm update regressions cover initial
phone sizing and resizing. Real Chromium checks cover 320/390/768/1280 pixel
layouts, keyboard navigation visibility, chat drafts/retries/history, and returning
from a conversation to the colleague list. Browser assertions wait for committed
Elm rendering. The PWA shell cache advances to v15 to deliver updated assets.
