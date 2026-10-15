# System administration and access levels

Sign in with an Administrator account and open **System administration** in the
sidebar, or visit `/administration`. Administration is restricted to the current
workspace. Other access levels cannot open its API or manage user accounts.

## Access levels

| Level | Read records | Create, edit and delete | Administration |
|---|---|---|---|
| Administrator | All workspace records | All workspace records | Users, teams, security, workspace settings and integrations |
| Manager | All workspace records | All workspace records | CRM ownership, client invitations and trash recovery |
| Member | Own records and records shared with their team or workspace | Create records; edit and delete own records | Own profile and account security |
| Viewer | Own records and records shared with their team or workspace | Read only | Own profile and account security |

Reports and exports follow the same read access. Private records are readable by
their owner, Administrators and Managers; team records also allow members of the
specified team; organization visibility allows every user in that workspace.
These are the four supported access levels, with a permission guide under
**Access levels**. Custom roles and per-module permission overrides are not included.

## Unsaved forms

Administration is rendered by Elm. Switching sections, refreshing this screen,
opening another account, creating a user, closing an edit, following a link or
signing out prompts with **Save**, **Discard** and **Stay** when the form changed.
Save continues only after the server accepts the change. Account-access changes
still require their confirmation. Validation, network and stale-version failures
keep entered values on the screen. Forms are held in memory; passwords are not
written to browser storage. Closing or reloading the browser uses its native unsaved-change warning through
a small port adapter; it does not use the Elm Save/Discard/Stay prompt.

## Manage accounts

1. Under **Users**, choose **Add user**, enter their name and email, and select
   their access level and team. An optional initial password creates an active
   account. Leaving it empty creates a disabled account with a single-use,
   72-hour invitation. The invitation is shown for sharing and queued for email.
2. Use search, level and status filters to find an account, then select **Manage**.
   Change its name, access level or team and choose **Save access**. Changes revoke
   all existing cookie sessions, refresh credentials and bearer tokens. Changes
   to your own account return you to sign-in.
3. **Disable account** blocks sign-in and invalidates sessions, invitations and
   password-recovery links. **Enable account** restores sign-in for a disabled
   account. Pending invitees must accept an invitation before activation.
4. **Renew invitation** replaces an outstanding or expired invitation; the old
   link becomes invalid. **Cancel invitation** keeps the account disabled and
   invalidates its invitation.
5. **Sign out all devices** revokes sessions without disabling the account.
   **Send password recovery** queues a single-use, 30-minute link to the account
   owner's email; the link is not returned to the administrator. **Reset two-factor
   authentication** removes the authenticator secret and recovery codes and signs
   the user out.

At least one active Administrator must remain. Access changes from this page
include the loaded account revision; another administrator's intervening change
causes a conflict and requires a refresh. Legacy administration API clients may
omit `If-Match` for compatibility.

**Teams** creates teams and shows account counts. Assignments are managed under
Users. **Security** shows the 100 most recent active sessions, account changes
with their actor, and login/security events. **Workspace settings** controls the
workspace name, timezone, reporting currency and IP allowlist, and links to the
existing integration settings. An allowlist must include your current network.

Invitation and recovery emails require configured SMTP. Manual invitation sharing
and creating accounts with an initial password work without email configuration.

## API

- `GET /api/admin/system`: workspace users, teams, role guide, sessions and audit.
- Existing `POST /api/admin/users`: invite or create an account.
- Existing `PATCH /api/admin/users/{user}`: name, role, team, disabled status and 2FA reset.
- `POST /api/admin/users/{user}/revoke-sessions`: revoke all current sessions.
- `POST /api/admin/users/{user}/invitation`: rotate a pending invitation.
- `POST /api/admin/users/{user}/password-reset`: queue account-owner recovery email.

User-specific changes accept `If-Match: <accessVersion>` from the administration
response. Invalid roles/teams, foreign-workspace users, outdated versions and
unauthorized roles are rejected by the backend. Failed transactions roll back
account, session, token and audit changes together.

## Verification

The Elm/Go build, full Go race-test suite, targeted administration/record-permission
race tests, Go vet, and all 11 DOM checks passed. Tests cover role and workspace
boundaries, session revocation, stale edits, invitation cancellation, last-admin
protection and transaction rollback. Browser smoke coverage now includes creating a
Viewer through this page and checking the access guide on mobile. That browser run
could not execute locally because Chromium closed during startup; live browser
acceptance remains unverified.
