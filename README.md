# ECC CRM

Elm frontend and Go API for contacts, deals, activities, tasks, schools,
students, agents, leads, cases, document tracking, invoices, payments, and partners.

## Features

- Conversational **Ask ECC AI** adviser throughout the workspace: ask follow-up
  questions, get advice on the current record, and plan your day. Saved conversations, source links and explicit staff confirmation for proposed
  actions. Optional realtime voice endpoints require separate configuration. Requires AI provider configuration and
  workspace activation; see [the AI guide](docs/EXPANSION.md#conversational-ai-adviser).

- Light and dark workspace themes, saved in the browser; grouped navigation,
  accessible contact links, readable tables, and consistent form labels.

- SQLite database with separate tables for all CRM modules, accounts, revoked
  sessions, and change history. Writes commit in a transaction; failed writes
  roll back the in-memory state too.
- Global search in the top bar: search names, emails, companies, phone numbers,
  and reference numbers across the full dataset. Results link to their records.
- Reports: live totals, CSV exports for every CRM module, and paginated change
  history showing the actor, record, action, and time.
- Contacts and activities, deals kanban, tasks, education and case workflows,
  invoices and payments, partner management, and profile/password settings.
- Browser session restore, deep links, and logout across all sessions.

## Run

Requires Elm 0.19.2 (`npm install -g elm@0.19.2-0`), Go 1.26 or newer, and a C compiler (such as GCC) for the
[SQLite driver](https://github.com/mattn/go-sqlite3#installation).

```bash
./build.sh
./build/ecc-crm
```

Open http://localhost:7000 and register the first workspace account. A fresh
installation starts empty. Set `ALLOW_SIGNUP=false` after creating the intended
accounts to require invitations. The container defaults to registration disabled;
for an empty container database, explicitly enable `ALLOW_SIGNUP=true` during
private first-time setup, create the owner account, then disable registration.

For a local demonstration only, start a fresh database with
`SEED_DEMO_DATA=true ./build/ecc-crm`. This explicitly enables sample records and
the public demonstration login `demo@northwind.dev` / `Demo1234`. Keep this flag
disabled in production. Existing demo accounts are not automatically removed;
change their credentials or disable them before exposing an existing demo database.

The same app supports phones and tablets with bottom navigation, record cards,
larger touch controls and mobile forms. See [docs/MOBILE.md](docs/MOBILE.md) for
phone access and verification details.

The maintained application is `src/`, `public/`, and `golang-backend/`.
Earlier implementations and unused style backups are preserved in `archive/`; see [archive/README.md](archive/README.md). They are excluded from the application build and Docker context.

## Database and migration

The default database is `data/crm.sqlite3`. On a new database, existing
`data/crm.json` records are imported automatically, including password hashes
and session versions. The JSON file is left untouched. Migration happens only
once: restarting uses the database, and empty tables are never reseeded.
Malformed legacy data stops startup rather than replacing it with demo data.

- `DATABASE_PATH`: SQLite database path.
- `LEGACY_DATA_FILE`: optional JSON source to import into a new database.
- `DATA_FILE`: legacy configuration compatibility; when `DATABASE_PATH` is
  unset, imports this JSON file into `crm.sqlite3` in the same directory.
- `PORT`: HTTP port, default `7000`.
- `JWT_SECRET`: set a long random secret for deployment. When unset, a private random secret is persisted in `data/auth-secret`.

Schema migrations use SQLite `user_version`. Record tables store one row per
record, with an ID, ordering, and JSON data; account credentials have dedicated
columns. Runtime handlers and workers load committed SQL into private request
state and persist guarded row changes. Separate-process regression tests cover
concurrent writes, startup, account changes and recurring workers. SQLite still
serializes writers; measure your workload before scaling. Processes sharing a
database must also share the deployment secrets and file storage. Make data
changes through the API.

Back up the database using SQLite's backup command so committed WAL data is included:

```bash
sqlite3 data/crm.sqlite3 ".backup 'data/crm-backup.sqlite3'"
```

Keep backups private: they include CRM records and password hashes. Database
files are excluded from Git and cannot be served by the app's static routes.
Existing accounts and records migrate into the default organization. New registrations
create isolated organizations. Administrators invite users into their own workspace.
Document files are stored privately beside the database and accessed through authenticated
version downloads. Serve behind an HTTPS reverse proxy for deployment.

## New API endpoints

These endpoints require an authenticated HttpOnly cookie session. Existing API
clients with a valid bearer token are also supported.

- `GET /api/search?q=...`: up to 30 results, with a truncation flag. Requires at
  least two characters. Search treats SQL wildcard characters as literal text.
- `GET /api/audit?limit=25&offset=0`: paginated change history; optional `actor` filter.
- `GET /api/exports/{entity}`: all accessible module records as CSV, Excel (`?format=xlsx`), or PDF (`?format=pdf`), with proper quoting and
  spreadsheet formula protection. Account credentials cannot be exported.

Change history starts with changes made after migration. Existing demo data is
not presented as a user action. Deleted record labels remain in the history;
passwords and tokens are never included in history entries.

## Verify

```bash
npm install
npm test
npm run test:workspace-next
elm make src/Main.elm --output=/tmp/ecc-crm-check.js
cd golang-backend
go test -race ./...
go vet ./...
```

Workspace styles live in `public/workspace.css`, scoped to the app shell.
The login branding remains in `public/styles.css`. Icons and charts use Elm SVG.


## Real-use workspace tools

Administrators can open **System administration** in the sidebar to manage users,
access levels, teams, invitations, account recovery and workspace security.
See [docs/ADMINISTRATION.md](docs/ADMINISTRATION.md) for the role matrix and steps.

Open **Workspace tools** in the sidebar for user invitations, roles/teams, record
visibility, sessions and 2FA, document versions, SMTP/outbox, imports, saved views,
calendar, workflows, commissions, and integration delivery history. Existing detail
pages link to the relevant tools; invoice pages also offer a PDF download.

The full feature and activation guide is [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).
[.env.example](.env.example) lists deployment settings. The server reads process
environment variables and does not automatically load `.env` files.

Back up `uploads/` beside the database and the generated `auth-secret` (or preserve
`JWT_SECRET`) along with SQLite. Losing the encryption secret makes saved SMTP and
TOTP secrets unreadable. Restore these together. External SMTP, Stripe, VAPID,
OIDC and SAML integrations require configuration before live use.

## Daily workflow expansion

Record pages now embed native tools, with a separate client portal, cohort reports,
inbound conversations, optional AI drafts, version conflicts, and recoverable deletion.
Docker/Compose, CI/CD, metrics and backup/restore scripts are included.
See [automatic testing and releases](docs/CI_CD.md); `npm run test:all` runs the full verification pipeline locally.
See [docs/EXPANSION.md](docs/EXPANSION.md) for setup, verification and remaining
provider/scaling limits. The older implementation checklist describes the previous
feature set; it is not a production acceptance record for this expansion.

## Daily work

See [docs/DAILY_WORK.md](docs/DAILY_WORK.md) for My work today, the unified student journey, navigation presets, inline form warnings, integration connection checks, SQL repository changes and verification.

See [lead intake from a CV](docs/LEAD_INTAKE.md) for direct Leads navigation,
referrer details, CV attachments before an application exists, reviewed AI fields,
and conversion into a client or student/application with document history.

See [lead work and requirements](docs/LEAD_WORK.md) for next actions, overdue lead
reminders, duplicate review, lead activity history, document responsibility and
deadlines, and source/referrer pipeline reporting.

## Next priorities

See [docs/ROADMAP.md](docs/ROADMAP.md) for implementation status and remaining acceptance work. SQL runtime isolation,
application handoffs and searchable application/invoice pickers are implemented.
Live integration acceptance and adviser/finance participation remain pending.

Workspace tools are grouped into Daily work, Finance, Data and Administration
with role and capability checks. Application essentials stay prominent; document
filters and paged Files lists support follow-up. See
[workflow validation](docs/WORKFLOW_VALIDATION.md) for local test evidence,
isolated restoration and the remaining staff/provider acceptance work.

See [real integration acceptance](docs/INTEGRATION_ACCEPTANCE.md) for the runnable
provider checks and [staff usability](docs/STAFF_USABILITY.md) for participant
tasks and observation recording. Live provider acceptance and actual staff
sessions remain pending.

See [operational improvements](docs/OPERATIONAL_IMPROVEMENTS.md) for faster
contact saves, application requirements, handoff reminders, duplicate receipt
checks and optional manager approval.

Record cleanup and historical assignment review: [workflow guide](docs/RECORD_CLEANUP.md).


## Offline work, full deal boards and record retention

Enable **Offline work** to cache opened CRM views on this device and queue edits
with conflict review on synchronization. See [mobile/offline use](docs/MOBILE.md).
Deal board filters and metrics now cover every accessible matching deal. Bulk
contact updates and deal changes require every selected record's revision and
commit atomically. Administrators manage trash eligibility, purge previews and
optional automatic cleanup in **Workspace tools → Trash**. See
[record conflicts and trash](docs/EXPANSION.md#record-conflicts-and-trash).

## Application workflow controls

Application stage gates, a unified client timeline, configurable manager escalations
and a progressively loaded deal board are available. Managers configure policies
and escalation rules in Workspace tools. See [Workflow controls](docs/WORKFLOW_CONTROLS.md)
for setup, permission behavior and verification.

## Usability and performance cycle

The daily work and application screens group actionable work and essential
fields, with expandable controls and draft recovery. **Workspace tools → Staff
usability** includes a two-session guide and a manager review of the three tasks
with the most recorded completion problems. Use the
[session worksheet](docs/STAFF_SESSION_WORKSHEET.md) to identify exact obstacles,
choose up to three fixes and retest them with staff. Actual participation and
findings remain pending.

Run `npm run test:performance` for an isolated workload with 5,000 contacts,
applications and documents. [Performance measurements](docs/PERFORMANCE.md)
records the current backend baseline, its limits and JavaScript component
ownership. Global search now uses SQL visibility checks and measures about 20
times faster in a fresh local comparison. Dashboard and daily-work aggregation
are the next profiling candidates. Browser loading and deployment-specific workloads need separate
measurement before choosing performance targets.

See [focused staff workflows](docs/WORKFLOW_FOCUS.md) for manager exception queues,
service templates, combined communication history, operational attention and the
simplified daily-work/application screens.

Communication controls and calendars now share consolidated workspaces. Bulk
contact updates use searchable selection and review; QR tools and adviser Deals
navigation are optional. Agents and partners share a directory while retaining
their own record types and financial rules. See
[consolidated workspace guide](docs/WORKSPACE_CONSOLIDATION.md).

Mobile navigation, workspace team chat, and printable management reports are documented in [Mobile, chat and reports](docs/MOBILE_CHAT_REPORTS.md).
