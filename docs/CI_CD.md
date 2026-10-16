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

Changes are on `ci/quality-gate` in
[PR #1](https://github.com/emannet2000/ecc-crm-myapp5/pull/1). Check that PR's
latest **Quality gate** result before merging; an earlier local pass does not
replace verification of the current commit.

Local validation has passed the full gate (58 browser checks, 40 frontend checks,
12 Python checks, backend race/vet/property checks and production compilation).
The automatic lead-reference tests also passed with race detection, and the
read-only lead form was verified in Chrome 152. Hosted runs exposed additional
browser synchronization issues; the tests now wait for refreshed forms and use
the staff-facing document upload action. Assertions remain enabled.

Security remediation is included: Go 1.26.9, go-jose v4.1.4 and goxmldsig v1.6.0.
The updated scanner reported zero reachable vulnerabilities; npm audit and Go
module checksum verification passed. Security reports are retained as Actions
artifacts, including after a failed scan.

The connected GitHub integration cannot administer branch protection. `main`
was last verified as unprotected. Render is not connected, so its deployment
settings and production health have not been changed or verified. An owner must
activate the settings above before this is an enforced production deployment
gate. Do not merge merely because the workflow exists.

Automated tests reduce risk; they do not prove the absence of bugs or establish
real provider delivery.
