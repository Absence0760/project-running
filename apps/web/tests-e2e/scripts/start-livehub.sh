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
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_KEY"
export HEALTH_PORT
export WORKER_ID="livehub-e2e"
# Force permissive (auth-OFF) mode. main.go auto-loads the committed
# apps/job_worker/.env.development, which sets SUPABASE_JWT_SECRET to the
# Supabase demo secret — that would flip the hub into Supabase-JWT auth
# and 403 the anon pushLivePing the spec relies on. loadEnvFiles only
# fills vars that are NOT already in the environment (os.LookupEnv), so
# exporting these empty here shadows the .env.development defaults and
# keeps the authorizer nil. The auth gate itself is covered by the Go
# unit tests (internal/livehub/auth_test.go, server_test.go).
export SUPABASE_JWT_SECRET=""
export LIVEHUB_REQUIRE_AUTH=""
exec "$BIN_DIR/jobworker-livehub-e2e"
