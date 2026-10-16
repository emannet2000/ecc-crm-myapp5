# Lead follow-up, history and application requirements

## Automatic lead numbers

The Lead number field is read-only. Saving a new inquiry assigns a reference such
as `ECC-LD-2026-00006`; staff do not fill it in. The year follows the workspace's
timezone, with a separate sequence for each workspace and year. Existing
references are retained on edits, and older blank references are assigned when
saved. The database counter prevents reuse after deletion or restart and keeps
simultaneous saves distinct. Existing random internal record IDs are unchanged.
Imports may still supply an existing reference when creating a record.

## Next action and overdue inquiries

Open a lead's **Next action and activity** panel. **Follow-up plan** saves the next
staff action, responsible consultant, follow-up date and status together. New
leads start with “Review inquiry and arrange first consultation”; replace this
with the specific next step. Older leads without an action remain visible as
needing a plan. The existing lead Edit form also includes the next action.

**My work today** shows the actual next action and an **Overdue lead follow-ups**
count. Overdue inquiries are urgent. Converted and Closed/Lost leads are excluded.
Staff can select All accessible work to review other assignments. Click any summary
count to show its matching records, next actions, owners, deadlines and record links.
Filtering applies before pagination; Show all work clears the selected category.
Summary controls stay visible while loading. Rapid clicks use only the latest
response, and failed requests can be retried with Refresh work. If an older running
server ignores the filter, the panel asks you to restart with the latest build.

The reminder worker creates at most one in-app reminder per lead and workspace
day when its follow-up is due or overdue. It uses the named/ID consultant when
that uniquely identifies an active account with record access, otherwise an
unassigned lead uses its record owner. Unknown, ambiguous, disabled or inaccessible
consultants receive no reminder. Changing the follow-up date or closing/converting
the lead retires existing unread follow-up reminders. Email notification delivery
continues to use the existing opt-in preference and SMTP configuration.

## Dashboard record views

Deals, Open pipeline, Leads, Students and Cases cards show paginated record details
and links. These categories cover all stages, including future or converted leads
and closed cases. Open pipeline excludes Won and Lost deals and shows each deal
value in its own currency. The assignment selector applies to these views; students
use record ownership. Existing dashboard summary cards open All accessible work
so their workspace-wide totals and record views agree. Existing record permissions apply.
These overview records are separate from the daily due-work queue.

## Duplicate review

Before saving a lead, the form checks matching email or normalized phone against
all accessible leads and contacts, including records beyond the first list page.
Warnings link to the matching records. Email matching ignores case and surrounding
whitespace; phone matching ignores formatting and treats `+` and international
`00` prefixes consistently. It does not guess country codes for local numbers.

The server repeats the check when creating an inquiry or changing its contact
details. If a match exists, saving requires **I reviewed matching records above;
this is a separate inquiry**. Shared family phones or genuinely separate inquiries
remain possible after review. Changing the email or phone clears that confirmation.
Unchanged contact details do not interrupt ordinary plan edits. The lead itself
and its converted contact are excluded from self-matches. Restricted identities
are not disclosed through duplicate hints. This is a review workflow, not a merge.

## Lead activity timeline

Log a call, message or note that has already happened. Logging a message does not
send one. Mark **This was an actual client follow-up** only for a performed call
or message; notes do not count as client follow-ups.

The paginated timeline combines logged activity, current notes, recorded status,
assignment, next-action and note changes, original CV upload/version history, and
document conversion history. History tracking starts with changes made after this
feature is installed. Existing uploaded file versions remain available. Current
notes are labeled as current content rather than an invented historical event.

After conversion, accessible conversations on the linked contact are labeled
**Linked contact**. They may span multiple inquiries; they are not presented as
messages belonging exclusively to this lead. Restricted cases and documents are
excluded. Timeline entries are served through the permission-checked lead endpoint,
not through the general workspace entries list.

## Application requirements

The existing **Application requirements** panel shows the application's adviser,
next action and deadline, plus a checklist of accessible required documents.
Incomplete and overdue items appear first. Each item shows its status, responsible
staff member and deadline, with a link to review the document.

Staff who can edit both the application and document can select responsible staff
and save a document deadline. Responsibility does not change record ownership or
access. Assignees must be active staff in the same workspace with access to both
records. Without a document deadline, the application next-action deadline is used;
the panel labels that fallback. Without an explicit assignee, it uses the
application adviser or document owner.

Balances, receipt approvals, refunds and handoffs remain visible as separate items
needing attention. Checklist counts cover accessible documents only and do not
certify that hidden requirements are complete. Finance items do not become new
stage gates. Expired verified documents still need review and prevent automatic
readiness when automatic document advancement is enabled. Saves reject stale edits.

## Pipeline reporting

**Reports → Performance reports → Lead pipeline by source and referrer** uses
lead creation-date cohorts. It shows inquiry counts, current Converted status,
conversion percentage, inquiries with no logged follow-up, overdue open inquiries,
and average hours to first logged follow-up with the number of timed records.

New leads have an exact creation timestamp. The first explicitly marked call or
message establishes the first-follow-up timestamp; later logs do not replace it.
Status edits, notes and CV uploads do not manufacture a first contact. Older leads
without precise creation times are excluded from latency averages. **Not measured**
is distinct from a measured zero. No logged follow-up does not prove that no
contact occurred. Reports cover accessible records, not inaccessible workspace data.

## Verification

Backend checks cover duplicate review and private identities, timeline pagination,
stale edits, first-follow-up timing, daily work, daily reminder deduplication and
retirement, cohort metrics, requirement assignment, permissions and deadlines.
Chromium verifies next-action edits, safe timeline text and pagination, plus the
live lead-to-application journey, explicit duplicate confirmation, requirement
assignment and source/referrer reporting using a temporary test workspace.
Actual staff usability sessions and live integration acceptance remain separate.

## Staff, reviews and save recovery

Lead, case and deal forms use active staff account selectors. New or changed
assignments save account IDs, while unchanged historical name assignments remain
editable. Staff must be active, non-viewer accounts in the same workspace with
record access; assignment does not grant access.

Use the explicit conversion action instead of setting lead status to Converted.
Linked converted leads cannot be reopened by changing status. Historical converted
leads without links can still use the conversion action to establish them.

Document tables distinguish an uploaded file from a reviewed version. Open the
exact version, then explicitly record its review. Reviewer and timestamp come
from the server. Review does not mean Verified; each new upload requires a new
review. Lead document reviews also appear in the activity timeline.

The common record-tools summary shows status, responsible staff, creation date,
next action and deadline across leads, cases, deals and students. Where deals or
students do not have a stored next action, the panel provides a review suggestion.

Failed form saves retain inputs. A stale lead plan offers Load current version
and keep draft, shows the current saved action/status, and asks staff to compare
before retrying. Background record notifications do not replace a dirty lead plan.
The staff session worksheet includes CV intake, conversion and recovery tasks;
actual Flor and finance sessions remain pending participant execution.
