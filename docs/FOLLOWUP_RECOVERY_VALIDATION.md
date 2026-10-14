# Follow-up, scope and recovery validation — 2026-10-14

Dashboard follow-ups use the organization's date: overdue is before today,
today is the same date, and upcoming is after today. The due total includes
only overdue and today. Upcoming includes every future recorded follow-up,
not only the next seven days. Missing or invalid dates are excluded from these
three dated totals. Closed/converted leads are excluded.

Dashboard cards open the same dated record sets, carrying assignment and branch
filters. AI follow-up reasons distinguish overdue, today, upcoming and missing
dates. AI attention applies mine (including unassigned), all, or unassigned
before ordering and limiting its results. Attention now loads tasks and deals
as well as applications and leads and checks record access for extra alerts.

## Regression checks

- Backend tests cover date boundaries, a follow-up 30 days away, all three AI
  assignment scopes, stage drill-down and branch filtering.
- `npm run test:dashboard-live` runs Chromium against an isolated real server and
  database. It covers dashboard clicks, scope and branch propagation, closed
  stage transitions, clearing stale stages, and 1280/390-pixel layouts. It also
  creates overdue, today and future leads and checks their returned record IDs.
- `npm test`, `go test ./... -timeout 2m`, `go vet ./...`, `./build.sh`, and
  `python3 tests/backup_test.py` provide the companion checks.

## Recovery and integration evidence

The current local SQLite database was archived with its generated auth secret,
restored into a separate temporary directory, and verified. All 49 table row
counts matched and SQLite integrity checks passed. The archive manifest was
verified. The restored server booted and the existing demo account logged in.
The local database had no document file versions; the backup regression suite
separately covers uploaded files, cleanup paths, archive traversal, and symlinks.

Private local artifacts are at `/tmp/ecc-local-recovery-b_wvnq6e/`:
`verification.json`, `integration-assessment.json`, `local-backup.tar.gz`, and
`restored/`. These are temporary local evidence, not committed customer data.

The acceptance runner executed against the restored server with sending disabled.
Email, WhatsApp, payments and AI all returned `not_configured`. The backend
signed payment callback regression covers signature rejection and duplicate
callback handling using a controlled fixture.

Actual inbox delivery, provider-signed live/test callbacks, provider failure and
retry acceptance remain pending. No designated acceptance URL, login credential
variables, recipient, contact, or test invoice were configured in this shell.
No deployment backup was supplied, so this exercise establishes recovery of the
current local data only; it does not establish recovery of a deployment backup.
See [integration acceptance](INTEGRATION_ACCEPTANCE.md) for the required provider
and recipient evidence. Do not record configuration probes as successful delivery.

## Additional fixes and acceptance gate

The shared My work / AI attention queue now labels overdue, today and upcoming
follow-ups separately. A missing next action remains visible alongside the date
reason, rather than replacing it. Future follow-ups with an action recorded
remain in the three-day attention window; records missing an action can appear
outside that window. Dashboard due totals continue to include only today and
overdue; its upcoming category covers every future recorded date.

My work displays the selected branch name and provides a Clear branch filter
button that preserves the category and assignment view. Show all work clears the
branch too. The server returns the applied branch ID/name, and the client reports
an error if the server does not apply a requested branch. Browser checks exercise
branch clearing at desktop and phone widths.

`npm run test:integrations:strict` rejects missing, unconfigured, pending and
partial integration evidence. Assessment mode retains its read-only default and
reports `acceptance.complete=false` even when its setup checks exit zero.
Policy and runner regressions verify these outcomes without provider calls.

`TestSMTPOutboxRejectsThenDeliversRetryOnce` exercises the real SMTP transport
against a controlled loopback inbox: recipient rejection, persisted retry,
message delivery with the expected recipient/body, and no second delivery after
success. This does not establish delivery through an external SMTP provider.

The final recovery rerun is recorded in `/tmp/ecc-final-recovery-f0swhda6/`.
It again verified all 49 table counts, database integrity, archive manifest and
preservation of the generated encryption secret. The restored server health and
login passed. `integration-assessment.json` records an incomplete assessment
with exit code zero; `integration-strict.json` records the same unconfigured
providers with exit code one. `runtime-verification.json` confirms strict mode
correctly rejected this incomplete evidence. No provider messages were sent.

Assignment changes preserve selected stage/branch filters so the displayed
heading continues to describe the records requested.
