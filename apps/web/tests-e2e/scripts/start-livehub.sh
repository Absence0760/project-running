#!/usr/bin/env bash
#
# Boot the Go job_worker's live-hub for the WebSocket spectator e2e
# (tests-e2e/live/spectator_websocket.spec.ts). Playwright's webServer
# block runs this and waits on the /health endpoint before the suite
# starts; it kills the process on teardown.
#
# Permissive mode on purpose: SUPABASE_JWT_SECRET and
# LIVEHUB_REQUIRE_AUTH are exported empty (below) so the hub accepts anon
# subscribe + unauthenticated push (the dev-only path documented in
# apps/job_worker/main.go). The zone fetcher IS wired (service role)
# so the privacy-zone clip still runs against the real seed — the test
# pushes points well clear of the seeded Sydney zone, same as the
# Supabase-Realtime spectator spec.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BACKEND_DIR="$REPO_ROOT/apps/backend"
WORKER_DIR="$REPO_ROOT/apps/job_worker"

HEALTH_PORT="${LIVEHUB_E2E_PORT:-8099}"

STATUS="$(cd "$BACKEND_DIR" && supabase status -o env)"
API_URL="$(printf '%s\n' "$STATUS" | grep '^API_URL=' | cut -d= -f2- | tr -d '"')"
SERVICE_KEY="$(printf '%s\n' "$STATUS" | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')"

if [ -z "$API_URL" ] || [ -z "$SERVICE_KEY" ]; then
  echo "start-livehub: could not resolve API_URL / SERVICE_ROLE_KEY from 'supabase status -o env'." >&2
  echo "start-livehub: is the local stack up? (cd apps/backend && supabase start)" >&2
  exit 1
fi

# Build to a temp path then exec it, so the running process IS this
# shell's replacement — Playwright's SIGTERM on teardown then reaps the
# hub cleanly instead of leaving a detached `go run` child behind.
# (exec replaces the shell, so no EXIT trap can clean BIN_DIR; the
# /tmp dir is a negligible leak the OS reclaims.)
BIN_DIR="$(mktemp -d)"
(cd "$WORKER_DIR" && go build -o "$BIN_DIR/jobworker-livehub-e2e" .)

cd "$WORKER_DIR"
export SUPABASE_URL="$API_URL"
export SUPABASE_SECRET_KEY="$SERVICE_KEY"
export HEALTH_PORT
export WORKER_ID="livehub-e2e"
# Force permissive (auth-OFF) mode so the anon pushLivePing the spec relies
# on isn't 403'd. The auth gate itself is covered by the Go unit tests
# (internal/livehub/auth_test.go, server_test.go).
#
# LIVEHUB_DISABLE_AUTH is the explicit opt-out. Emptying SUPABASE_JWT_SECRET
# is no longer sufficient on its own: the hub also derives a verifier from
# SUPABASE_URL via the project's JWKS, and SUPABASE_URL must stay set for
# zone and run-meta lookups. The two lines below still shadow the committed
# apps/job_worker/.env.development defaults (loadEnvFiles only fills vars not
# already in the environment), which keeps the boot log honest.
export LIVEHUB_DISABLE_AUTH="1"
export SUPABASE_JWT_SECRET=""
export LIVEHUB_REQUIRE_AUTH=""
exec "$BIN_DIR/jobworker-livehub-e2e"
