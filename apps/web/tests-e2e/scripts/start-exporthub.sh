#!/usr/bin/env bash
#
# Boot the Go job_worker for the queued Art 20 export e2e
# (tests-e2e/settings/export_job.spec.ts). Playwright's webServer block
# runs this and waits on the /health endpoint before the suite starts;
# it kills the process on teardown.
#
# Unlike start-livehub.sh this runs AUTH ON, and it must: the export
# endpoints refuse with 503 when no token verification is configured,
# and the whole point of the spec is that the archive built is the
# caller's own. The same process serves the endpoints AND drains the
# queue — main.go wires the worker's DataExport builder on the same
# condition as the endpoints, so there is one thing to boot.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BACKEND_DIR="$REPO_ROOT/apps/backend"
WORKER_DIR="$REPO_ROOT/apps/job_worker"

HEALTH_PORT="${EXPORTHUB_E2E_PORT:-8098}"

STATUS="$(cd "$BACKEND_DIR" && supabase status -o env)"
API_URL="$(printf '%s\n' "$STATUS" | grep '^API_URL=' | cut -d= -f2- | tr -d '"')"
SERVICE_KEY="$(printf '%s\n' "$STATUS" | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')"
ANON_KEY="$(printf '%s\n' "$STATUS" | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"')"
STATUS_JWT="$(printf '%s\n' "$STATUS" | grep '^JWT_SECRET=' | cut -d= -f2- | tr -d '"' || true)"

if [ -z "$API_URL" ] || [ -z "$SERVICE_KEY" ]; then
  echo "start-exporthub: could not resolve API_URL / SERVICE_ROLE_KEY from 'supabase status -o env'." >&2
  echo "start-exporthub: is the local stack up? (cd apps/backend && supabase start)" >&2
  exit 1
fi

# The signing secret, in decreasing order of authority: an explicit
# override, whatever `supabase status` reports, then the CLI's own
# documented local default. The default is a guess, so it is VERIFIED
# below rather than trusted — a wrong secret would surface as a 401 in
# the middle of a spec, which reads as a broken app rather than as a
# misconfigured harness.
JWT_SECRET="${SUPABASE_JWT_SECRET:-${STATUS_JWT:-super-secret-jwt-token-with-at-least-32-characters-long}}"

verify_secret() {
  # An anon key is a JWT the stack signed with exactly this secret, so
  # re-deriving its signature proves the secret without minting anything.
  local token="$1" secret="$2" signing sig want
  signing="${token%.*}"
  want="${token##*.}"
  sig="$(printf '%s' "$signing" \
    | openssl dgst -sha256 -hmac "$secret" -binary \
    | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  [ "$sig" = "$want" ]
}

if [ -n "$ANON_KEY" ] && ! verify_secret "$ANON_KEY" "$JWT_SECRET"; then
  echo "start-exporthub: SUPABASE_JWT_SECRET does not verify the local stack's anon key." >&2
  echo "start-exporthub: every export request would 401. Export the right secret and re-run:" >&2
  echo "start-exporthub:   SUPABASE_JWT_SECRET=<the stack's JWT secret> pnpm test:e2e:exporthub" >&2
  exit 1
fi

# Build to a temp path then exec it, so the running process IS this
# shell's replacement — Playwright's SIGTERM on teardown then reaps the
# worker cleanly instead of leaving a detached `go run` child behind.
BIN_DIR="$(mktemp -d)"
(cd "$WORKER_DIR" && go build -o "$BIN_DIR/jobworker-exporthub-e2e" .)

cd "$WORKER_DIR"
export SUPABASE_URL="$API_URL"
export SUPABASE_SECRET_KEY="$SERVICE_KEY"
export SUPABASE_JWT_SECRET="$JWT_SECRET"
export HEALTH_PORT
export WORKER_ID="exporthub-e2e"
exec "$BIN_DIR/jobworker-exporthub-e2e"
