# Automated quality gate and releases

`.github/workflows/verify.yml` runs on every push, pull request, merge queue,
manual dispatch and daily at 21:00 UTC (05:00 Manila). No path filters bypass
verification. Daily runs fuzz each property target for 60 seconds; other runs
use five seconds.

The checks are:

- Source: Go formatting, JavaScript syntax and shell syntax.
- Verification: optimized compilation of all four production Elm entry points
  and Go, backend unit/integration/regression tests with race detection and
  coverage, `go vet`, property fuzzing, Python tests, JavaScript units, executable
  Elm update/invariant checks, and sequential browser workflows including offline
  recovery. Elm checks use `tests/elm/AdministrationChecks.elm` through the Node
  harness; this repository does not use `elm-test` or a separate Elm formatter.
- Security: npm dependency audit including development tools (high/critical
  findings block), Go module checksum verification and `govulncheck` for reachable
  vulnerabilities. These checks need network access to vulnerability databases.
- Container: build the production Dockerfile and smoke-test startup, packaged
  assets and rejection of demo credentials. This now runs for pull requests too.
- **Quality gate**: always runs after the jobs above and fails if any failed,
  were cancelled, or were skipped. Use this stable name as the required check.

Dependencies are installed with `npm ci` from the committed lockfile. Test
artifacts are kept for 14 days even after failures. A passing main/version-tag
push also publishes the tested image to
`ghcr.io/emannet2000/ecc-crm-myapp5`, tagged with the full commit SHA and branch
or version. Pull requests never log into the registry or publish images.

## Activate GitHub protection

After pushing this workflow and completing its first successful run, open
repository **Settings → Rules → Rulesets**, create an active branch ruleset for
`main`, and require:

1. A pull request before merging.
2. Status checks: **Quality gate**, with the branch up to date before merging.
3. Block force pushes and branch deletion; do not give normal development a
   bypass. Require a reviewer if another maintainer is available.

These are GitHub account settings; committing workflow YAML does not turn them
on. Required checks must come from the latest commit. The final job uses
`always()` because a skipped dependent job alone can otherwise appear successful.
See [GitHub required-check troubleshooting](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

Normal development:

```sh
git switch -c feature/my-change
# edit, commit, then:
git push -u origin feature/my-change
# Open a pull request; merge only after Quality gate passes.
```

## Activate Render gating

For the existing Render service, open **Settings → Build & Deploy**, confirm the
linked branch is `main`, and set **Auto-Deploy → After CI Checks Pass**. Set its
health check path to `/api/health`. Keep its current environment variables,
persistent disk and database path. This repository does not create or replace a
production service or migrate production data.

Render then waits for the new main commit's CI checks before deploying, including
when someone pushes directly to main. Branch protection separately prevents that
normal development path. See [Render deployment settings](https://render.com/docs/deploys).
For a service already managed by a Blueprint, the equivalent setting is
`autoDeployTrigger: checksPass`; see the
[Blueprint reference](https://render.com/docs/blueprint-spec).

After deployment, verify `/api/health`, login/logout, and one read-only workspace
view on the production URL. Render's health check is automatic; this repository
cannot claim a production browser smoke test without a configured service URL
and test account. A failed CI run blocks deployment; a failed production health
check requires investigation before retrying.

## Run locally

Install Go matching `golang-backend/go.mod`, Node 24, Python 3, Chromium and the
QR/PDF tools (`qrencode`, `zbar-tools`, `poppler-utils`), then run:

```sh
npm ci
bash scripts/check-source.sh
npm run test:all
npm audit --audit-level=high
(cd golang-backend && go mod verify && govulncheck ./...)
docker build -t ecc-crm:local .
CRM_IMAGE=ecc-crm:local ./scripts/test-container.sh
```

Install the scanner with
`go install golang.org/x/vuln/cmd/govulncheck@v1.1.4`.
Set `CHROME_PATH` for a system browser, and `ECC_FUZZ_TIME=60s` for longer fuzzing.
Container smoke tests create and remove only their temporary container/volume.

## Activation status

The workflow and local checks are repository changes. GitHub branch protection
and Render settings must be activated in their dashboards by an authorized
account. No production deployment or external configuration change has been
performed from this workspace. Hosted Actions and actual Docker execution must
pass before this gate is considered proven. Automated tests reduce risk; they
do not prove the absence of bugs or establish real provider delivery.

### Initial local security result

The initial scan with the project's Go 1.26.0 toolchain exited nonzero and
reported **40 reachable vulnerabilities** across the standard library and two
modules: `github.com/go-jose/go-jose/v4@v4.0.5` and
`github.com/russellhaering/goxmldsig@v1.4.0`. Scanner-reported fixes include
Go 1.26.9, go-jose v4.1.4 and goxmldsig v1.6.0. Review compatibility and run the
full gate after updating; those upgrades are not part of this pipeline change.
The security job retains its full scanner output as `security-artifacts`, even
when it fails. Local output is in `tests/artifacts/security/govulncheck.txt`.
Do not disable the security requirement to obtain a green release. npm audit
reported zero vulnerabilities and Go module checksum verification passed.

### Initial local verification result

Workflow lint (`actionlint` v1.7.7), source checks, production Elm/Go build,
backend race tests and `go vet`, five property fuzz targets, 12 Python tests,
and all 40 frontend unit checks passed. Backend statement coverage was 58.3%.
The browser run completed with **55 passed, 3 failed, no skipped tests**:

- `tests/browser.test.cjs:253`: live login/native workflows/mobile test timed out.
- `tests/browser.test.cjs:1087`: recovered-draft rejected-save test timed out.
- `tests/consolidation.browser.cjs:12`: login email input was not found.

`npm run test:all` therefore exited 1. These browser failures require diagnosis;
they have not been disabled or declared harmless. The full local log is
`tests/artifacts/quality-gate-local.log`. Actual Docker execution was unavailable
because Docker is not installed. No hosted workflow run, branch protection change,
Render setting change or production deployment was performed.

### Follow-up remediation

The backend now requires Go 1.26.9; Docker uses the same patched version.
go-jose was updated to v4.1.4 and goxmldsig to v1.6.0, with their required
etree/clockwork updates. A new `govulncheck` run completed successfully with
**zero reachable vulnerabilities** (one advisory remains in a required module
whose affected code is not called).

The three failed browser workflows all passed a focused retest after adding
UI-readiness waits and foregrounding the keyboard-focus test. The assertions
for login, focus, stale-save rejection, draft retention and confirmed-save cleanup
are unchanged. The complete suite is being revalidated against the patched build.
Changes are prepared on `ci/quality-gate`, keeping production on `main`.
