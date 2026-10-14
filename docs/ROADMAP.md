# Next priorities

For the current implementation and acceptance status, start with [Current revision status](CURRENT_REVISION_STATUS.md). The dated sections below preserve earlier implementation evidence and planning history.

## Requested next improvements — 2026-10-12

The first four priorities are implemented and locally verified. Isolated backup
restoration and integration configuration assessment are complete on a synthetic
workspace. Actual adviser/finance sessions, live provider acceptance and a
restoration of a deployment backup remain pending external details. See
[workflow validation](WORKFLOW_VALIDATION.md) and [performance results](PERFORMANCE.md).

| Priority | Improvement | Completion criteria |
| --- | --- | --- |
| 1 | Simplify Workspace navigation | Group tools into Daily work, Finance, Data and Administration. Show links appropriate to each role and capability, preserve existing deep links, and verify keyboard and mobile navigation. Server permissions continue to enforce access. |
| 2 | Reduce repeated application information | Keep owner, stage, next action, deadline and missing documents prominent. Collapse duplicate document lists, counts and secondary controls while preserving access to history and editing actions. Verify the resulting layout on desktop and phone. |
| 3 | Make document follow-up faster | Add missing, overdue and expiring document filters with clearly stated date rules. Provide direct actions to assign responsible staff and deadlines. Preserve record visibility, unsaved entries and revision checks, and refresh affected counts after saves. |
| 4 | Improve large-workspace performance | Profile remaining aggregation costs using representative records. Measure complete browser loading and time until work is usable, alongside backend latency and allocations. Record controlled before/after results on the same hardware and dataset while preserving permissions, totals and ordering. |
| 5 | Validate real workflows | Run adviser and finance sessions using the staff worksheet, complete live integration acceptance in a designated test environment, and restore a backup into an isolated environment. Record actual outcomes, turn obstacles into reproducible issues, implement the highest-impact fixes and repeat affected checks. |

Use [performance measurements](PERFORMANCE.md), the
[staff session worksheet](STAFF_SESSION_WORKSHEET.md) and
[integration acceptance guide](INTEGRATION_ACCEPTANCE.md) to capture evidence.
Actual staff participation, configured provider accounts and a designated restore
environment are needed to complete the corresponding validation. Do not contact
participants automatically or count automated fixtures as real staff sessions.

## Review follow-up — 2026-10-12

Home now puts My work today first. Message/overdue totals, manager exceptions,
operational alerts and recent changes sit in separate expandable sections.
Manager sections retain their existing role checks. The optional AI brief stays
capability-controlled. These changes reduce the initial screen's competing
summaries. Automated browser review passed; actual staff validation remains pending.

Recommendations at the start of this review (later status is recorded above):

1. Group Workspace tools into daily work, finance, data and administration, with
   role-appropriate links and preserved deep links.
2. Keep application owner, stage, next action, deadline and missing documents
   prominent; review secondary fields and repeated record controls with staff.
3. Extend server-backed searchable selectors to remaining workflow forms,
   referral partners and linked applications, preserving existing relationships.
4. Profile dashboard and daily-work aggregation against the documented baseline,
   then measure browser loading before and after changes.
5. Complete live provider acceptance, isolated backup restoration and adviser/
   finance sessions, recording actual results rather than inferred readiness.
6. Split the Workspace tools controller by workflow and review overlapping DOM
   observers, with consistent request cancellation, retry and lifecycle cleanup.

Remove repeated counts, navigation entries and setup explanations where they
duplicate an existing workflow. Keep Deals, QR, AI and offline tools optional
until usage evidence supports retirement; do not delete their records as part
of interface simplification.

## Verification follow-up — 2026-10-12

The five requested improvements are present in the workspace: application essentials
group stage, responsible staff, action, deadline and document requirements; workspace
forms retain failed-save drafts and offer explicit conflict review; collapsed Home
sections show attention counts and unavailable states; workflow relationships use
searchable record pickers, including referral partners and linked applications; and
daily-work/dashboard measurements are recorded in [PERFORMANCE.md](PERFORMANCE.md).
Superseded picker searches are cancelled on new input, selection and disconnection.

Build, all five frontend suites, backend tests and the full backend race check
passed. The desktop/phone improvement
browser check exercised a failed save, concurrent edit, records beyond the first
page, keyboard selection, summary retry and mobile overflow. This is automated
verification; live integrations and actual staff sessions remain pending.

## Next usability and performance improvements

The table below retains acceptance criteria for continued review. Automated
verification above does not complete actual staff acceptance or deployment profiling.

| Improvement | Intended result | Acceptance criteria |
| --- | --- | --- |
| Searchable selectors everywhere | Staff can find partners and linked applications without scrolling through dropdowns. | Remaining record relationship selectors use server-backed search and pagination, retain saved selections, support keyboard access, and handle loading, empty and retry states. Search and saves enforce record visibility. |
| Clear application essentials | Owner, next action, deadline and missing documents stay visible together. | Staff can identify the responsible person and next task from one section on desktop and phone. Documents link to the required action; secondary details remain expandable. |
| Useful collapsed summaries on Home | Staff know which closed sections need attention. | Section summaries show accessible ownership and delivery issue counts with loading and unavailable states. Counts match their expanded content and refresh after relevant changes. Avoid duplicate totals and do not label a failed request as zero issues. |
| Faster daily-work loading | The first usable screen appears sooner. | Profile aggregation and browser rendering on a representative dataset; record before/after request times, allocations and time until the work list is usable. Preserve permissions, totals and ordering. |
| Consistent save and recovery behavior | Staff retain their entries after failures and can recover clearly. | Network, validation and stale-version failures preserve entered values, identify the problem and offer retry or conflict review. Background refresh does not replace a dirty form. Successful saves have a clear confirmation. |
| Real workflow validation | Changes address obstacles experienced by advisers and finance staff. | Use the existing staff worksheet for actual participant sessions, record completion/time/errors/help, implement the highest-impact findings and retest affected tasks. Participation and findings remain pending until sessions occur. |

Use the existing [staff session worksheet](STAFF_SESSION_WORKSHEET.md),
[performance baseline](PERFORMANCE.md) and
[integration acceptance guide](INTEGRATION_ACCEPTANCE.md) when recording evidence.


Implementation status as of 2026-10-10: SQL runtime isolation, application
handoffs, searchable application/invoice pickers and staff observation recording
are implemented. Separate-process and browser verification cover the software.
Live providers and actual staff participation are still pending. See
[Daily work](DAILY_WORK.md), [integration acceptance](INTEGRATION_ACCEPTANCE.md)
and [staff sessions](STAFF_USABILITY.md).

| Priority | Improvement | Why it matters | Status |
| --- | --- | --- | --- |
| 1 | Finish the SQL migration | Committed SQL state prevents stale process data; large-workspace validation remains expensive. | SQL runtime migration and separate-process tests complete; costly projections remain. |
| 2 | Test real integrations end to end | A successful connection check does not prove email delivery, WhatsApp replies, payment callbacks, or AI responses work. | Runner and checklist ready; live providers pending. |
| 3 | Make application handoffs explicit | Show the current owner, next action, due date, and who takes over next. | Implemented; backend and browser checks pass. |
| 4 | Add searchable record pickers | Staff should find any accessible student, contact, or application without relying on loaded dropdown options. | Implemented in application/invoice forms; search and keyboard checks pass. |
| 5 | Run adviser and finance usability sessions | Automated tests establish functionality; staff feedback reveals what is confusing or slow. | Observation form and task guide ready; actual participants pending. |

## 1. Finish the SQL migration

Move remaining CRM mutations, validation, account/security handlers, workflow
reads, and background workers to scoped SQL repositories. Preserve ownership,
workspace isolation, related-record visibility, revision checks, audit history,
and transaction rollback behavior.

Acceptance criteria:

- Runtime requests and workers use committed SQL rather than a shared mutable
  memory cache; bootstrap/import code is separate from normal operation.
- Tests cover concurrent edits, worker execution, account/session revocation,
  startup, and workspace boundaries across separate backend processes.
- Repeat the documented realistic workload benchmarks and record read latency,
  write latency, and allocations before and after the migration.
- Remove the one-process restriction only after the implementation and tests
  demonstrate that separate processes cannot lose updates or duplicate work.

Separate-process regression checks now pass. SQLite still serializes writers,
and large writes retain costly workspace projections. Measure deployment-specific
load and share secrets/file storage before scaling; this is not a production
capacity claim.

## 2. Test real integrations end to end

Use a designated acceptance environment, configured provider accounts, approved
test recipients, and Stripe test mode. Connection checks remain an initial setup
step, not the acceptance result.

Acceptance criteria:

- Email: confirm delivery to a test inbox, reply ingestion and association with
  the intended record, plus understandable failure and retry states.
- WhatsApp: confirm an outbound message and inbound reply are attached to the
  correct conversation, including repeated webhook delivery and provider errors.
- Payments: exercise checkout, signed callbacks, invoice/payment updates, replay
  protection, and failed or cancelled checkout without duplicate payments.
- AI: verify an actual response, accessible source links, saved conversation
  history, explicit confirmation for actions, viewer restrictions, and failure
  handling for unavailable providers or exhausted limits.
- Record the environment, date, expected result, observed result, and sanitized
  provider references for each scenario. Never put credentials in test reports.

Live execution depends on configured accounts and a supplied testing environment
and recipients. Do not mark these checks passed based on mocked tests alone.

## 3. Make application handoffs explicit

Add a visible handoff state to the application and student journey: current owner,
next action, due date, proposed receiving staff member, and handoff status.

Acceptance criteria:

- Staff can propose a handoff with its reason and expected next action; the
  receiving staff member can accept or decline it.
- The current owner remains responsible until an authorized handoff is accepted.
- Pending, accepted, declined, and cancelled handoffs appear in record history.
- Receiving staff and owners see pending or overdue handoffs in their daily work.
- Permissions, workspace boundaries, and stale changes are checked on the server.

## 4. Add searchable record pickers

Replace limited student, contact, and application dropdowns with server-backed
search and pagination, starting with application and invoice forms.

Acceptance criteria:

- Staff can find accessible records beyond the first loaded page.
- Keep the selected record visible while searching, loading, or editing an
  existing record; opening a form must not silently clear a stored relationship.
- Show useful distinguishing details for similarly named records, plus loading,
  empty, and retry states. Ignore responses to superseded searches.
- Support keyboard selection, visible focus, labels, and mobile touch controls.
- Search and saves enforce access rules without exposing inaccessible records.

## 5. Run adviser and finance usability sessions

Ask actual advisers and finance staff to complete everyday tasks in a test
workspace. Prepare the sessions without contacting participants automatically.

Suggested tasks:

- Adviser: identify today's highest-priority application, find its missing
  documents, update the next action, and hand it to another adviser.
- Adviser: find a student in a large dataset and review their application and
  portal response without losing context.
- Finance: find an application, create its invoice, record a test receipt, and
  explain the remaining balance and any pending approval.
- Both: recover from a failed integration or stale edit, then repeat a key task
  on a phone using keyboard access where applicable.

Acceptance criteria:

- Record completion, time, errors, requests for help, and participants' comments
  for each task. Keep participant information and customer data private.
- Turn observed obstacles into reproducible issues, ordered by their impact on
  task completion rather than assumed importance.
- Implement the highest-impact fixes and repeat the affected tasks with staff.
- Report actual findings separately from automated test results. Sessions remain
  pending until advisers and finance staff participate.
