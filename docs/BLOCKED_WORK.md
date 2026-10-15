# Explaining blocked application work

Open an application and look under **Application essentials → Application
requirements → What is blocking progress**. The same summary appears with
application requirements in the student journey.

The summary previews the immediate next stage using the configured stage rules.
It lists unmet conditions, the responsible staff member or manager role, the
deadline when available, and a link to review the document or stage approval.
The approval link opens stage readiness with the destination stage selected.

Automatic submission readiness appears separately when the application has
auto-advance enabled. Document follow-up, balances, pending receipts and handoffs
remain visible below; reminders alone do not become stage blockers. The summary
also shows the application's next action and deadline.

An unconfigured stage gate is labelled explicitly. The preview does not approve,
advance or override an application. Existing transition validation still decides
whether a requested move is allowed. Restricted document names remain redacted
when they affect a stage rule. Responsibility and deadlines use existing record
assignments; an unset deadline is shown as “Not set”.

Verification: focused backend tests cover next-stage scope, disabled policies,
restricted documents and existing finance/reminder behavior. Browser tests cover
the summary and approval link on desktop and mobile, existing document controls,
and the student journey.

## Suggested actions and document requests

Expand **Suggested next actions and document request** in Application requirements.
Missing, expired and correction-required files produce client follow-up suggestions;
uploaded files produce staff-review suggestions. Stage requirements can also
suggest requesting manager approval.

Choose **Review as next action**, then **Use this suggestion** in the next-action
editor. If you already have an unsaved action, replacing it requires a separate,
explicit button. Review the deadline and choose **Save next action** to persist
the plan. Existing revision/conflict checks still apply. The student journey
includes an editor beside its suggestions.

The document-request draft includes accessible required documents that are
missing, expired or marked Correction Required. Completed files and files only
awaiting internal review are excluded. Select documents and use **Rebuild message
from selection** to generate the wording, then edit and copy it. Rebuilding
replaces the current message text. Dates come from existing requirement deadlines;
review them before using the message. No message is sent by these controls.

Edited request drafts and next-action drafts are kept during background refreshes.
Use **Discard draft and refresh** to reload the document list when ready. Clipboard
failure selects the message for manual copying. Existing access controls determine
whether staff can save a next action.

Browser verification covers selection and copy, internal-review exclusions,
preservation of edited drafts, stale-save rejection and successful next-action
saves through the Go API on desktop and mobile.
