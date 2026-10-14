# Mobile web version

Open the same CRM address in your phone or tablet browser and sign in with your
existing account. User roles, private records and administration permissions apply
on every screen size. The client portal and invitation/password-recovery pages
also adapt to phones.

On screens up to 900 pixels wide, bottom navigation provides **Home**, **Clients**,
**Cases**, **Tasks**, and **More**. More opens the full module menu, including
System administration for Administrators. Close the menu with its close button,
the backdrop or Escape. Focus stays inside the open menu and returns when it
closes; background content cannot receive accidental taps while it is open.

At phone widths up to 600 pixels, ordinary record and administration tables become
labelled cards. Record links, action buttons, sorting controls and pagination keep
their existing behavior. Tables with grouped or spanning cells retain their table
layout and scroll within their container. Larger screens retain the desktop tables.

Controls have larger touch targets and form fields use a 16-pixel font. Phone edit
forms use the available screen height; confirmation dialogs open as bottom sheets.
Layouts allow space for display cutouts and the home indicator. Deal boards scroll
horizontally between stages. On supported browsers, install ECC CRM from the
in-app **Install ECC CRM** button or the browser menu. On iPhone/iPad, open the app
in Safari, use **Share**, then **Add to Home Screen**. Installation requires HTTPS
in production; localhost is supported for development.

The service worker keeps the public app shell available offline. To save CRM data,
sign in online and open **Offline work → Enable offline work** on a device you
control. Open the views you need while connected: those responses are then stored
privately for that account on this device. Cached lists can open their record
details offline. Saved views are snapshots and may be out of date; uncached views
and searches need a connection. Up to 250 responses are retained.

Offline work supports edits to existing contacts, deals, tasks, schools, students,
agents, leads, cases and partners, including deal stages, task status and next-action
plans. Each edit needs the record's cached server revision. The app stores up to
100 pending drafts in IndexedDB and displays them in **Offline work**. Edits remain
pending until server validation succeeds. Uploads, new records, deletion, bulk
changes, payments, administration and live communication need a connection.
Document files and photos are not cached.

Reconnection triggers sync while the app is open. Browsers with Background Sync
can also retry queued work; **Sync pending edits** is always available. Sync uses
the original account, current permissions and each record's original revision.
Conflicts stay pending for **Compare with saved record**, followed by an explicit
retry or discard. Invalid or unauthorized edits remain blocked. Signing out,
changing accounts, or **Disable and clear device data** removes saved responses
and drafts. Browser storage eviction can remove local data; pending drafts should
be synchronized before clearing browser data. Offline sign-in to a different
account is unavailable; the previously enabled account can resume from its cached
profile.

## Open it on a phone

Use the reachable address of your CRM deployment. `localhost:7000` on your phone
refers to the phone itself, not the computer running ECC CRM. For testing on the
same local network, open `http://<computer-LAN-IP>:7000`, provided the host's
network/firewall permits it. Configure `APP_URL` to the same reachable address so
invitation links work on the phone too. Production access should use the deployment's
HTTPS address and existing secure-cookie configuration.

This is a responsive web version. It uses the existing frontend and backend and
does not require a separate mobile account, App Store package or Play Store package.

## Verification

`npm test` includes checks for mobile table updates, retained record actions and
sorting, shadow-DOM tables, drawer focus and inert state, desktop resizing, dialog
scroll locking, and online/offline status. Browser smoke coverage checks 320-, 390-
and 768-pixel viewports, mobile navigation, form sizing and administration access.
Browser execution requires an environment where Chromium can launch; local DOM
checks do not verify final visual layout or a physical phone's keyboard behavior.


Offline browser verification: `npm run test:offline`. To also exercise the native
Elm editor against a temporary Go server, build `build/ecc-crm` and run
`ECC_BROWSER_LIVE=true npm run test:offline`.

## Phone interface revision — 2026-10-14

Phone sign-in uses a light neutral surface, persistent field labels, a 54-pixel
primary action and a 44-pixel password visibility control. Email/password autofill,
authenticator/recovery codes and organization sign-in remain available. Fields use
16-pixel text and keyboard action hints. The desktop sign-in layout is retained.

Mobile work cards display the next action, responsible staff, deadline and available
application document requirements together. Tool forms use larger controls and
single-column fields; workspace navigation groups use two-column touch buttons.
Home summaries and dashboard breakdowns are expandable. Bottom navigation includes
the configured phone destinations and respects the device's safe area.

On browsers exposing the visual viewport, bottom navigation and floating launchers
hide while a focused text field's keyboard reduces the viewport by more than
150 pixels. They return when the keyboard closes. Physical iOS/Android keyboard
behavior still needs device validation; browser automation checks responsive layout,
password visibility, mobile Home and chat interactions at 320, 390 and 768 pixels.
Preview screenshots are written by `npm run test:mobile-chat` to
`tests/artifacts/mobile-login.png`, `mobile-home.png` and `mobile-chat.png`.
