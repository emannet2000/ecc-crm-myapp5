#!/usr/bin/env bash
set -euo pipefail
: "${CRM_IMAGE:?Set CRM_IMAGE to the locally built image}"
container_name="ecc-crm-smoke-${RANDOM}"
cleanup() { docker logs "$container_name" || true; docker rm -fv "$container_name" >/dev/null || true; }
trap cleanup EXIT
# Bind an ephemeral port to avoid conflicts with other local test runners.
docker run -d --name "$container_name" -p 127.0.0.1::7000 \
  -e APP_URL=http://localhost -e ALLOW_SIGNUP=false -e SEED_DEMO_DATA=false "$CRM_IMAGE"
port="$(docker port "$container_name" 7000/tcp | sed 's/.*://')"
base="http://127.0.0.1:$port"
ready=false
for attempt in $(seq 1 60); do
  if curl --fail --silent "$base/api/health" >/dev/null; then ready=true; break; fi
  sleep 1
done
if [ "$ready" != true ]; then echo 'Container health check failed' >&2; exit 1; fi
for asset in /elm.js /public/account-elm.js /public/record-browser-elm.js /public/work-dashboard-elm.js /public/work-dashboard-elm.css /public/management-report-elm.css /account/forgot-password; do
  curl --fail --silent "$base$asset" >/dev/null
done
status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data '{"email":"demo@northwind.dev","password":"Demo1234"}' "$base/api/login")"
if [ "$status" != 401 ]; then echo 'Fresh release unexpectedly accepts the demo login' >&2; exit 1; fi
