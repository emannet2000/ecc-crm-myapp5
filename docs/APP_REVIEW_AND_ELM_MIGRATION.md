# App review and Elm migration

Updated 2026-10-15. Findings below distinguish source inspection, passing automated checks and remaining acceptance gaps.

## Fix priorities

| Priority | Finding | Evidence | Recommended fix |
| --- | --- | --- | --- |
| Fixed | Record browsing previously mixed concurrent replies. | `src/RecordBrowser.elm` owns queries, pagination, results and generation checks. The legacy function now only mounts Elm and passes saved query state. | Deliberately delayed search and module replies pass the browser regression. |
| Fixed | Administration previously discarded unsaved forms. | Administration now uses `src/Administration.elm`; the custom element has been retired. | Elm provides Save, Discard and Stay, and retains drafts after rejected saves. |
| Medium | Session recovery differs between screens. | Team chat has migrated to Elm and refreshes/retries through `src/Frontend/Http.elm`. `public/usability.js:26` still lacks refresh; remaining JavaScript screens need a consistent policy. | Apply one refresh-and-retry policy and preserve unsent chat text and form entries. Verify refresh failure and simultaneous expired requests. |
| Fixed | Record-browser controls previously exposed field-name inputs. | Elm now provides named sort options and column checkboxes, plus header sorting. | Native browser regression passes. |
| Medium | Security history is difficult to interpret. | `src/Administration.elm` security tables renders backend timestamps and event identifiers directly; backend events include codes such as `admin.sessions_revoked:<id>`. | Format dates with an explicit timezone and translate known actions into readable labels, resolving target users where possible. Keep unknown events visible. |
| Improved | Workspace timezone entry previously required technical knowledge. | `src/Administration.elm` now offers city/zone suggestions, keeps custom valid IANA zones and explains automatic daylight-saving rules. | A current-time preview remains to be added. |

## Acceptance gaps

The current revision status records pending actual adviser/finance sessions, mobile retests, live provider delivery/replay checks and deployment performance measurements. These are unverified areas, not confirmed defects. Follow `STAFF_SESSION_WORKSHEET.md` and `INTEGRATION_ACCEPTANCE.md`; automated fixtures do not establish actual staff or provider acceptance.

The compiled Elm harness now runs 81 regression checks and 2,000 generated navigation/date cases. The frontend unit suite passes with temporary test dependencies. Integration acceptance policy checks passed (4 tests). Targeted Go administration/access checks and the full Go suite passed.

## Elm migration scope

The app already uses Elm for routing and many CRM views. Administration, Team chat, account recovery, management reports, the record browser and Home/work dashboard now render from Elm; their former handwritten JavaScript screen files have been removed. Remaining handwritten JavaScript includes separate custom-element screens and browser infrastructure. Physical line count understates complexity because several files have long, compressed lines.

Move UI state, forms, validation, HTTP decoding, loading/error states and navigation into Elm. Preserve existing routes and API contracts. Use typed per-feature models and messages rather than expanding a single unstructured model.

Suggested order:

1. Completed: Administration, including users, access levels, teams, security and workspace settings. Unsaved-form protection is implemented. Timezone presentation still needs refinement.
2. Completed: primary management reports and Home/dashboard work queues. Remaining: operational outcome, priority and analysis summaries.
3. Record tools: lead/document work, assignments, handoffs, workflow controls and progress.
4. Workspace tools, pickers and secondary workflows.
5. Completed: Team chat and account recovery. Remaining: AI, portal and staff usability screens.
6. Offline and browser infrastructure: move their visible UI into Elm; reduce browser code to explicit ports.

Keep a small JavaScript adapter for startup, storage, DOM focus/measurement where needed, camera access, download URLs and browser APIs unsupported by Elm packages. Service workers still execute JavaScript in a separate browser context. Generated `elm.js` remains JavaScript by definition. Converting Node test runners is a separate testing decision, not an application UI migration.

For each migrated feature: compile Elm, exercise existing backend tests, replace DOM tests that depend on removed custom elements with behavioral browser checks, and verify roles, stale edits, failure recovery, mobile layout and keyboard access. Remove a legacy script only after confirming all entry points have moved. Avoid running old and new implementations of the same screen simultaneously.
