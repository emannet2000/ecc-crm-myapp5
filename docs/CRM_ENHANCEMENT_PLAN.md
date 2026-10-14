# ECC-CRM App4 enhancement plan

Date: 2026-10-13. Scope: analyse the existing application, then enhance the
dashboard, the lead-to-completion workflow, and AI assistance **without**
rewriting the system, deleting functionality, or changing the schema
unnecessarily.

---

## 1. What the system is today

### 1.1 Architecture

| Layer | Technology | Entry points |
| --- | --- | --- |
| Frontend | Elm 0.19.1, compiled with `--optimize` to `elm.js` | `src/Main.elm`, `build.sh` |
| Enhancement UI | ~25 vanilla-JS web components mounted into the Elm DOM | `public/*.js`, loaded in `index.html` |
| API | Go 1.26, `net/http` `ServeMux`, single `package main` (~32k LOC, 117 files) | `golang-backend/main.go` |
| Database | SQLite (WAL, `synchronous=FULL`, `MaxOpenConns(1)`), JSON-in-SQL rows | `golang-backend/database.go` |
| Tests | Go `net/http/httptest` + `node --test` (linkedom DOM + puppeteer Chromium) | `golang-backend/*_test.go`, `tests/*.cjs` |

Middleware chain (`main.go:174`):
`observeHTTP(protectHTTP(persistMutations(mux)))` — metrics/logging → security
headers and CSRF → per-request SQLite transaction plus runtime projection.

### 1.2 Routing

`main()` registers routes inline **plus** two helpers; those helpers fan out into
nine more registration functions (`golang-backend/main.go:45-167`).

```
main.go
├── registerWorkspaceRoutes      control_center.go:13
│   ├── registerConsolidatedRoutes      consolidated_workspace.go:22
│   │   └── registerEverydayRoutes       everyday_work.go:12
│   ├── registerAdministrationRoutes     administration.go:12
│   ├── registerDocumentRoutes           document_files.go:17
│   ├── registerDataRoutes               data_tools.go:81
│   ├── registerWorkflowRoutes           workflows.go:36
│   ├── registerPaymentRoutes            payment_gateway.go:18
│   ├── registerIdentityRoutes           identity_providers.go:21
│   └── registerExpansionRoutes          expansion.go:25
│       ├── registerDailyRoutes             daily_work.go:17
│       │   └── registerProductivityRoutes  record_productivity.go:12
│       ├── registerTeamChatRoutes         team_chat.go:10
│       ├── registerPortalRoutes           portal.go:12
│       ├── registerConversationRoutes     conversations.go:19
│       ├── registerAssistantRoutes        assistant.go:20
│       └── registerRecordPhotoRoutes      record_photos.go:22
└── registerFollowupRoutes       followups.go:42
```

≈190 API routes in total. **A new endpoint must be registered in the matching
`registerXxxRoutes` function, not in `main.go`.**

### 1.3 Domain model

13 entity tables (`database.go:17`), each `(id, sort_order, data JSON)`:
`contacts, deals, activities, tasks, schools, students, agents, leads, cases,
documents, invoices, payments, partners`. Plus 23 supporting tables
(`organizations, teams, users, sessions, audit_events, case_stage_events,
workspace_entries, application_gate_rules, ai_*, portal_access, conversations,
mail_outbox, notifications, trash_*, …`).

Staff-facing vocabulary maps to storage as: **Applications = `cases`**,
**Clients = `contacts`**, **Invoices & payments = `invoices` + `payments`**.

Stage/status vocabularies (exact strings, do not change):

| Entity | Field | Values |
| --- | --- | --- |
| Lead | `status` | New, Contacted, Qualified, Consultation Booked, Proposal Sent, Converted, Closed/Lost |
| Case | `currentStage` | Assessment, Eligibility Review, Agreement Pending, Documents Pending, Documents Under Review, Application Preparation, Partner Review, Ready for Submission, Submitted, Additional Documents Requested, Decision Pending, Approved, Refused, Closed |
| Case | `priority` | Low, Medium, High, Urgent |
| Document | `status` | Not Requested, Requested, Received, Under Review, Correction Required, Verified, Expired |
| Task | `status` | todo, in_progress, done |
| Payment | `status` | posted, pending_approval, void, refund, refund_reversal |
| User | `role` | admin, manager, member, viewer |

### 1.4 Access control

- There is **no branch entity**. The only sub-organisation grouping is
  **`teams`** (`users.team_id`, `records.teamId`) plus record visibility
  `organization | team | private`. Confirmed: `grep -ri branch` over the Go and
  Elm sources returns nothing.
- Every record embeds `RecordScope{OrgID, OwnerID, TeamID, Visibility}`
  (`access.go:14`).
- Predicates: `canRead` (`access.go:63`) and `canWrite` (`access.go:68`).
- SQL reads filter with `scopeSQL` / `repositoryVisibility`
  (`access.go:363`, `repository.go:52`); legacy handlers instead receive an
  already-projected store.
- **Write authorisation is centralised**, not per handler: `scopedHandler`
  (`access.go:207`) projects the store to what the caller may read, blocks
  `viewer` writes, re-checks `canWrite` on every changed record, verifies
  `If-Match` revisions, rejects dangling relations, and enforces application
  stage gates after the handler runs.
- `manager` and `admin` see the whole organisation; `member` sees own + team +
  organisation-shared and writes only own; `viewer` is read-only.

---

## 2. Existing CRM modules and workflows

| Requested module | Present? | Where |
| --- | --- | --- |
| Dashboard / My work | Yes | `GET /api/my-work` → `<crm-my-work>` (`public/components.js:259`) |
| Leads | Yes | `leads.go`, `lead_work.go`, `lead_pipeline.go`, `lead_intake.go` |
| Clients / contacts | Yes | `contacts.go`, `data_tools.go` (merge, bulk, import, duplicates) |
| Applications (cases) | Yes | `cases.go`, `stage_gates.go`, `application_blockers.go`, `handoffs.go` |
| Students | Yes | `students.go`, student journey endpoint |
| Documents | Yes | `documents.go`, `document_files.go`, `document_review.go`, versions + expiry |
| Invoices / payments | Yes | `finance.go`, `receipt_controls.go`, `payment_gateway.go`, `reconciliation.go` |
| Tasks / follow-ups | Yes | `tasks.go`, `followups.go` (rules, history, queue), `productivity_reminders.go` |
| Reports | Yes | `reports.go`, `insights.go`, `workspace.go` (audit, CSV/XLSX/PDF export) |
| Administration | Yes | `administration.go`, `control_center.go`, `session_security.go`, `identity_providers.go` |
| AI assistance | Yes | `assistant.go`, `assistant_chat.go`, `ai_agent.go`, `ai_tools.go`, `ai_knowledge.go`, `ai_actions.go`, `ai_voice.go` |
| Communication / portal | Yes | `communication.go`, `conversations.go`, `portal.go`, `team_chat.go` |
| Calendar | Yes | `consolidated_workspace.go` (`/api/workspace-calendar`) |
| Integrations | Yes | `integration_health.go`, `mailbox_sync.go`, Stripe, WhatsApp, OIDC/SAML, VAPID push |
| Mobile / PWA | Yes | `public/mobile.css`, `mobile.js`, `pwa-sw.js`, `offline-worker.js` |

---

## 3. Feature-by-feature gap analysis

### 3.1 Phase 2 — Dashboard

| Reference-CRM concept | Status | Evidence |
| --- | --- | --- |
| Professional layout, clear sidebar | **Exists** | `src/View/Layout.elm`, `Views.elm:377`, CSS tokens in `public/workspace.css` |
| Active cases | **Exists** | `/api/my-work` count `applications` + `cases` |
| Open leads | **Exists** | counts `leads`, `followups`, `overdueLeads` |
| Follow-ups due | **Exists** | counts `followups`, `overdueLeads`, `deadlines` |
| Payments due | **Partial** | count `invoices` exists, but no due/overdue split, no amounts, no currency separation on the dashboard |
| Clickable KPI cards | **Exists** | 16 count buttons in `<crm-my-work>`, each re-queries `/api/my-work?category=` |
| **Case-stage summary** | **Missing on the dashboard** | `caseStages` is computed by `/api/reports` (`reports.go:19,72`) but rendered only on the Reports page (`public/reports.js:21`) as a static table. It is not on Home and not clickable |
| **Document-completeness indicator** | **Partial** | `documents` count = "applications with a document needing review". Per-application checklist exists (`/api/cases/{id}/blockers`). No workspace-level completeness roll-up (e.g. applications complete / incomplete / in review, required vs verified) |
| **Branch-specific operational overview** | **Missing entirely** | `teams` exist (`control_center.go:161` create, `:89` list) and drive record visibility, but there is no team-scoped dashboard, team selector, or per-team operational roll-up |

**Gap 2-A — case-stage summary on the dashboard.** New backend roll-up + clickable
stage cells that open the matching applications.
**Gap 2-B — document-completeness panel.** Roll up required/verified documents per
active application and bucket applications into complete / incomplete / in review.
**Gap 2-C — payments-due panel.** Split outstanding invoices into overdue, due this
week and later; keep amounts separated per currency (never summed across
currencies, per existing policy in `docs/OPERATIONAL_IMPROVEMENTS.md`).
**Gap 2-D — branch (team) overview.** Aggregate the same metrics per team, with a
selector. Managers/administrators may pick any team; members are fixed to their own
team. **The team filter is applied on top of record visibility, never instead of
it** — a team view can never widen access.

### 3.2 Phase 3 — Business workflow

Chain: Lead → Qualification → Client/Student → Application → Document collection
→ Submission → Decision → Completion.

| Requirement | Status | Evidence / gap |
| --- | --- | --- |
| Preserve relationships | **Exists** | `Case.clientId/ studentId / parentCaseId`, `Document.caseId/leadId`, `Invoice.caseId`, `Payment.invoiceId`; `danglingDeletedRelations` blocks deletes that would orphan children (`access.go:332`) |
| Avoid duplicate client creation | **Exists** | `convertLead` reuses a contact by email (`lead_intake.go:131`), refuses when a matching contact exists but is not writable (`:151`), and `POST /api/leads` repeats the check (`lead_work.go:33,70`) |
| Lead → client/student conversion | **Exists** | `contact` / `application` / `student` targets, idempotent (`lead_intake.go:107`), documents reparented without changing IDs (`:198`) |
| Track case/application status | **Exists** | `case_stage_events` append-only history (`insights.go:379`), `/api/cases/{id}/stage-history` |
| Validate documents before submission | **Exists** | `stage_gates.go` — policies per destination stage requiring upload / review / verified / manager approval, with override + reason |
| Generate follow-up tasks | **Partial** | Configurable rules (`followups.go:614`) and the `lead-convert` workflow action can create tasks (`workflows.go:262`). Nothing generates a task on **stage transitions** or on **submission/decision** |
| Audit trail of important changes | **Exists** | `scopedHandler` writes `audit_events` for every change (`access.go:317`), plus `workspace_entries`, `case_stage_events`, `client-history`, gate approvals, handoff history |
| Backend role/branch enforcement | **Exists** | Centralised `scopedHandler` + `scopeSQL`; see §1.4 |

**Gap 3-A — no automatic follow-up task on application stage change.** A stage
move to a stage with no next action, or to `Ready for Submission` / `Submitted` /
`Decision Pending` with unmet requirements, produces no work item. Add an
idempotent, auditable task so the transition actually lands in someone's queue.
**Gap 3-B — no single "submission readiness" roll-up.** `application_blockers.go`
computes per-case blockers, but the dashboard cannot summarise readiness, and
there is no server-side "validate mandatory documents" call that returns a single
machine-readable readiness verdict for a case. Add `GET /api/cases/{id}/readiness`
returning the gate + blocker verdict, reuse it on the dashboard.

### 3.3 Phase 4 — AI assistance

The AI layer is already substantial and must be **extended, not replaced**:

- `aiAgent.run` (`ai_agent.go:164`) runs up to 5 tool rounds, re-checking
  authorisation between rounds (`aiStillAuthorized`), and re-validating every
  source reference each round (`aiReferencesAllowed`).
- Tools: `search_crm`, `read_record`, `search_knowledge`, `analyze_workspace`,
  `propose_action`.
- **No write occurs inside a model tool.** `propose_action` returns
  `{"state":"awaiting_user_confirmation"}` and staff confirm in the UI
  (`POST /api/assistant/actions/{action}/confirm`).
- Sources are re-verified for record access and content before each turn, so the
  model cannot cite revoked or newly hidden records.

| Requested question | Current behaviour | Gap |
| --- | --- | --- |
| What needs my attention today? | `analyze_workspace` returns `attention` built by `aiAttention` (`ai_tools.go:258`) | Present |
| Which clients have missing documents? | model must improvise `search_crm` calls | **No grounded, structured tool** |
| Which cases are overdue? | `analyze_workspace` gives `overdueCases` as a number only | **No record list** |
| Which applications are ready for submission? | — | **Unsupported** |
| Which clients need follow-up? | model must search | **No grounded tool** |
| What payments are overdue? | `analyze_workspace` gives balances by currency | **No record list** |

**Gap 4-A — no deterministic, authorised "insights" tool.** The model must guess
which records to fetch, which is the main hallucination risk. Add one read-only
tool, `workspace_insights(topic)`, that answers these six questions from the same
scoped SQL the dashboard uses and returns record IDs the UI turns into source
links. It must:
- reuse `readScopedRows`/`repositoryVisibility` so it can never widen access;
- return IDs only, never invent rows;
- have no write path at all;
- re-verify each returned record with `sqlRecord` before it is cited.

### 3.4 Duplicated / overlapping code found

Recorded for later cleanup, **not** changed in this cycle:

- Seven overlapping summary endpoints: `/api/control-center`, `/api/reports`,
  `/api/insights`, `/api/my-work`, `/api/workspace-priorities`,
  `/api/operations/attention`, `/api/work-outcomes`.
- `operationalReport` is computed by both `/api/insights` and
  `/api/workspace-priorities`.
- Four independent duplicate-detection implementations:
  `/api/data-quality`, `extendedRecordAudit`, `/api/duplicates`,
  `leadDuplicateCandidates`.
- `View/Home.elm` still contains a dead `managementChartsView` +
  `statCard` + donut/gauge/heatmap helpers, and `model.reports` is fetched on
  Home purely to feed that dead code.
- `<crm-reports>` (`public/reports.js`) duplicates the Elm Reports page.

---

## 4. Implementation plan (incremental, reviewable)

### Step 1 — Dashboard backend
New `golang-backend/dashboard_overview.go`:
`GET /api/dashboard/overview` returning case-stage counts, document completeness,
payments-due buckets (per currency), open leads / follow-ups, and a team
(branch) roll-up. Reuses `readScopedRows`, `canRead`, `workAssigned`,
`activeApplication`, `documentNeedsReview`, `organizationToday`, `dateDistance`.
Team filtering applies **after** visibility. Registered in `registerDailyRoutes`
and added to `independentDailyRead` so it is not blocked by the mutating
middleware path.

### Step 2 — Dashboard drill-downs
Extend `/api/my-work` categories with `caseStages`, `documentComplete`,
`invoicesOverdue`, `invoicesDueSoon` so every new KPI opens the existing paged
record list. No new list UI.

### Step 3 — Dashboard UI
New `public/dashboard-overview.js` defining `<crm-dashboard-overview>`; rendered
from `src/View/Home.elm`. Clicking any KPI dispatches a `crm:dashboard-focus`
event that `<crm-my-work>` consumes (reusing its existing category/offset
machinery). Add `<script>` to `index.html`. CSS uses the existing ECC token set
in `public/components.css`.

### Step 4 — Workflow
- `GET /api/cases/{id}/readiness`: single machine-readable submission-readiness
  verdict reusing `evaluateStageGate` + `handleApplicationBlockers` logic.
- Automatic, idempotent, audited follow-up task on qualifying stage transitions.

### Step 5 — AI
`workspace_insights` tool (read-only) in `golang-backend/ai_insights.go`, wired
into `agentTools`, sources added through `addSource`, answers restricted to the
six operational topics.

### Step 6 — Tests and docs
Go regression tests for each new endpoint and role/branch restriction; a node DOM
test for the dashboard component; update this document and `docs/ROADMAP.md`.

---

## 5. Constraints honoured

- No module, route, table or record type is removed.
- No schema change is required by this plan (step 1 and 5 read existing columns;
  step 4 writes to existing `tasks`).
- No mock data in production paths.
- Existing tests, build and `go vet` are re-run after every step.

## 6. Known limitations of this plan

- "Branch" is implemented as the existing **team** concept, agreed with the
  project owner. Records whose visibility is `private` and whose owner is on a
  different team will not appear in another team's overview, by design.
- Amounts are never summed across currencies; the payments panel is per currency.
- Document completeness reflects **accessible** required documents only. It does
  not certify that hidden requirements are complete — existing wording in
  `docs/LEAD_WORK.md` is preserved.
- Stage summaries use the fixed `validCaseStages` list; unknown stages stored by
  older data are shown under "Unspecified" rather than dropped.