# Communication, calendars and optional modules

## Communication

Open **Communication** in the sidebar or Workspace tools. Email outbox entries,
incoming/outgoing WhatsApp messages and client portal responses appear in one
paged history. Search by message or client name and filter by channel. Managers
can select **Unmatched messages**, search for a client and attach a message.
The sender information retained in an unmatched subject stays in its history.

**Write to a client** provides searchable client selection and the configured
email/WhatsApp channels. Email retains recipient, subject, delivery state and
retry details. WhatsApp keeps its existing reply-window and server permission
checks. Only staff permitted to retry a queued email see its retry action.
Unconfigured sending and read-only access leave history available.

**Send an invoice PDF**, **Client portal access** and **Inbox connection** are
expandable sections in this workspace. Client portal invitations retain their
existing manager-only creation/revocation checks. The client-facing portal is
unchanged. SMTP acceptance does not establish inbox delivery; uncertain delivery
still requires provider evidence before retrying.

Record Communication tabs show the relevant client, application, invoice or
student's application messages. Access checks include every linked record.
Old Email, Communication history, Unmatched inbox and Client portal tool links
open the consolidated workspace; existing APIs and record histories are retained.

## Calendar

Open **Calendar** in the sidebar or Workspace tools. Choose a month and event
type to see tasks, application deadlines, lead follow-ups, document deadlines and
expiry, unpaid invoice due dates, student actions/travel and recorded consultations.
The agenda is paged, with links back to the source records. Completed tasks,
closed applications/leads and paid invoices are excluded from outstanding work.

Consultations use the workspace timezone when choosing their calendar day and
displaying their time, including appointments that cross midnight in UTC. They
retain their original records. This consolidation does not send invitations or
change external calendar connections.

## Bulk contact updates

Open **Workspace tools → Data & views → Bulk contact update**. Search contacts,
select checkboxes across pages, choose the new stage and select **Review selected
contacts**. Remove an unwanted selection using its named Remove button.
Select **Update reviewed contacts** after checking the latest names, emails and
before/after stages. There is no need to enter record IDs.

The limit remains 500 contacts. Review checks that every selected contact is
editable and captures its current revision. A change after review rejects the
whole update. The selection remains available; review again before retrying.
Changing the selection or target stage invalidates the previous review.

## Tool access

QR tools are available in Workspace tools as **Scan QR**, and in record tools
as **QR code**. Deals is available under **All modules**. Navigation focus and
optional visibility switches have been removed; existing permissions still apply.

## Agents and partners

Open **All modules → Agents & partners** or its Workspace tools tab. Search both
record types together or filter to Agents/Partners. Entries show their type,
commission rate and available agreement dates, and open the existing record.
Manage agents/partners links retain the original list and creation/editing flows.
No record types, commissions, agreements or payout histories are merged.

## Verification

Backend regression checks cover channel history, workspace/private/parent
visibility, student scoping, authentication, pagination, timezone boundaries and
combined directory types. The live browser check uses an isolated temporary
database and exercises selections across pages, an actual stale bulk save,
portal/email history, unmatched-message linking, calendar filters, optional tools,
directory filtering and phone layout.

```sh
cd golang-backend
go test ./... -timeout 120s
go build -o ../build/ecc-crm .
cd ..
npm run test:consolidation
```

Provider delivery remains separate from these local checks.
