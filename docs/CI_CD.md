# Automatic testing and releases

GitHub Actions runs `.github/workflows/verify.yml` on every push and pull request, on manual dispatch, and daily at 21:00 UTC (05:00 in Manila). The daily run fuzzes each property target for 60 seconds; other runs use five seconds.

The verification job calls `npm run test:all`. That command builds all Elm entry points and the Go server, runs backend tests with race detection and coverage, runs `go vet`, fuzzes the property targets, checks the Python tools, runs frontend units against production Elm, and runs the browser regression files sequentially. Coverage reports, screenshots and other test artifacts are retained for 14 days, including after failures. A failed check prevents the container-release job from running.

Successful pushes to `main` or a `v*` tag build the Docker image, start a fresh container, verify health and frontend assets, and confirm that the public demo credentials cannot sign in. Only after those checks pass does the pipeline push the tested image to `ghcr.io/emannet2000/ecc-crm-myapp5`. Images carry a full commit SHA tag plus the branch or release tag; the run summary records the image digest. The package job alone receives `packages: write`; pull-request checks receive no publishing permission.

This uses the documented [GitHub Container Registry publishing pattern](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images), with Docker actions pinned to commits. The repository's GitHub token authenticates publishing. For a private package, the deployment host needs its own package-read credentials.

## Running locally

Install Go 1.26, Elm 0.19.2 (`npm install -g elm@0.19.2-0`), Node 24, Python 3, test dependencies (`npm install`), Chromium/Puppeteer and the application's QR/PDF command-line tools. Run:

```sh
npm run test:all
```

Set `CHROME_PATH` when Chromium is installed outside Puppeteer's managed browser path. Set `ECC_FUZZ_TIME=60s` for longer property runs. The script stops at the first failure and exits nonzero.

To smoke-test an image already built locally:

```sh
CRM_IMAGE=ecc-crm:local ./scripts/test-container.sh
```

The smoke test creates and removes only its own temporary container and anonymous volume. It does not attach the production data volume.

## Deployment status

Automatic image publication is configured. Deployment to a running environment still needs the target server or hosting service and its credentials. No production deployment has been performed from this workspace. Deployment configuration will be added once the target is selected, using the tested image digest and a health check.

Hosted GitHub Actions and Docker execution have not yet been verified from this machine; Docker is not installed here. Local app compilation and targeted regressions are verified separately in `RELIABILITY_AUDIT.md`. These checks do not establish real provider delivery or complete backend function coverage.
