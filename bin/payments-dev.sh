#!/usr/bin/env bash
#
# payments-dev.sh — local payments testing loop (Stripe + RevenueCat).
#
# Boots the local Supabase stack, serves the Edge Functions with
# .env.local loaded (so REVENUECAT_WEBHOOK_SECRET is set), and starts
# `stripe listen` forwarding to the local revenuecat-webhook handler —
# all from one command. Plus a `replay` that POSTs a correctly-signed
# RevenueCat event, which is the only path that actually exercises the
# happy path (tier flip) locally.
#
# Usage:
#   bin/payments-dev.sh start              # supabase + functions serve + stripe listen
#   bin/payments-dev.sh replay [TYPE] [PRODUCT] [APP_USER_ID]
#                                          # signed RevenueCat event → local handler
#   bin/payments-dev.sh status             # what's up / configured
#   bin/payments-dev.sh stop               # stop the functions-serve process
#   bin/payments-dev.sh help
#
# Wrapped by the root package.json:
#   pnpm dev:payments            -> start
#   pnpm dev:payments:replay     -> replay   (pass args after --)
#   pnpm dev:payments:status     -> status
#   pnpm dev:payments:stop       -> stop
#
# Prerequisites:
#   • Docker running (the Supabase stack runs in containers)
#   • supabase CLI            (brew install supabase/tap/supabase)
#   • stripe CLI + logged in  (brew install stripe/stripe-cli/stripe && stripe login)
#   • node + openssl + curl   (node ships with the repo toolchain)
#
# Why `replay` exists: the revenuecat-webhook handler REQUIRES an
# `x-revenuecat-hmac` header (HMAC-SHA256 of the raw body keyed by
# REVENUECAT_WEBHOOK_SECRET). `stripe listen` forwards RAW Stripe
# events with no such header, so those deliveries return 401
# (missing_signature) at the RC handler — expected, not a bug. The full
# Stripe → RevenueCat → our-handler loop needs a public tunnel so
# RevenueCat (cloud) can re-emit to localhost; `replay` short-circuits
# that for local dev by signing a RevenueCat-shaped event ourselves.
# See docs/testing/local_testing_stubs.md § Stripe.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ---- configuration --------------------------------------------------------

BACKEND_DIR="$REPO_ROOT/apps/backend"
ENV_FILE="$BACKEND_DIR/.env.local"
EXAMPLE_ENV="$BACKEND_DIR/.env.example"
API_BASE="${SUPABASE_API_URL:-http://127.0.0.1:54321}"
WEBHOOK_URL="$API_BASE/functions/v1/revenuecat-webhook"
# The seed user (runner@test.com) from apps/backend/supabase/seed.sql.
# Starts on the free tier, so an INITIAL_PURCHASE replay flips it to pro.
SEED_USER_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"

FN_PID=""   # background functions-serve pid (set by cmd_start)

# ---- helpers --------------------------------------------------------------

# Echo the REVENUECAT_WEBHOOK_SECRET value from .env.local (empty if the
# file or key is absent / blank). Reads the last assignment, strips
# surrounding quotes and whitespace.
read_secret() {
	[[ -f "$ENV_FILE" ]] || return 0
	local line v
	line="$(grep -E '^[[:space:]]*REVENUECAT_WEBHOOK_SECRET[[:space:]]*=' "$ENV_FILE" | tail -1 || true)"
	[[ -n "$line" ]] || return 0
	v="${line#*=}"
	v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
	printf '%s' "$v" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

supabase_running() {
	supabase --workdir "$BACKEND_DIR" status >/dev/null 2>&1
}

webhook_reachable() {
	# Any HTTP response (even 401/503) means the endpoint is serving.
	curl -s -o /dev/null -X POST "$WEBHOOK_URL" 2>/dev/null
}

ensure_env_file() {
	if [[ ! -f "$ENV_FILE" ]]; then
		warn ".env.local missing — copying from .env.example"
		cp "$EXAMPLE_ENV" "$ENV_FILE"
		ok "created $ENV_FILE"
	fi
}

cleanup() {
	if [[ -n "$FN_PID" ]] && kill -0 "$FN_PID" 2>/dev/null; then
		log "stopping functions serve (pid $FN_PID)"
		kill "$FN_PID" 2>/dev/null || true
		wait "$FN_PID" 2>/dev/null || true
	fi
}

# ---- subcommands ----------------------------------------------------------

cmd_start() {
	need_cmd supabase
	need_cmd stripe
	need_cmd node
	need_cmd curl
	docker info >/dev/null 2>&1 || fatal "Docker isn't running — start Docker Desktop first."

	ensure_env_file
	local secret; secret="$(read_secret)"
	if [[ -z "$secret" ]]; then
		warn "REVENUECAT_WEBHOOK_SECRET is empty in .env.local."
		warn "The webhook returns 503 (webhook_not_configured) until it's set."
		warn "Set any value (e.g. REVENUECAT_WEBHOOK_SECRET=whsec_local_dev) and re-run."
		warn "Use the SAME value with 'replay' so the HMAC matches."
	fi

	step "Supabase local stack"
	if supabase_running; then
		ok "already running"
	else
		log "starting (first run pulls images — can take a minute)…"
		supabase --workdir "$BACKEND_DIR" start
		ok "started"
	fi

	step "Edge Functions (with .env.local)"
	# `supabase start` auto-starts an edge runtime that ignores
	# .env.local, so REVENUECAT_WEBHOOK_SECRET would be unset → 503.
	# Re-serve with the env file (mirrors the edge-functions CI job).
	supabase --workdir "$BACKEND_DIR" functions serve --env-file "$ENV_FILE" &
	FN_PID=$!
	trap cleanup INT TERM EXIT
	log "functions serve pid $FN_PID — waiting for the endpoint…"
	local i
	for i in $(seq 1 40); do
		if webhook_reachable; then break; fi
		sleep 0.5
	done
	if webhook_reachable; then
		ok "serving at $WEBHOOK_URL"
	else
		warn "endpoint not responding yet — it may still be starting; watch the logs below"
	fi

	step "Stripe CLI → webhook forwarder"
	dim "'stripe listen' forwards RAW Stripe events. The RevenueCat handler"
	dim "needs an x-revenuecat-hmac header, so forwarded events return 401"
	dim "(missing_signature) — expected. For the real tier-flip happy path:"
	dim "  bin/payments-dev.sh replay        (or: pnpm dev:payments:replay)"
	log "starting 'stripe listen' — Ctrl-C stops everything…"
	echo
	# Foreground: Ctrl-C here triggers the EXIT trap → cleanup().
	stripe listen --forward-to "$WEBHOOK_URL"
}

cmd_replay() {
	need_cmd node
	need_cmd openssl
	need_cmd curl

	local etype="${1:-INITIAL_PURCHASE}"
	local product="${2:-pro_monthly}"
	local user="${3:-$SEED_USER_ID}"

	local secret; secret="$(read_secret)"
	[[ -n "$secret" ]] || fatal "REVENUECAT_WEBHOOK_SECRET is empty in $ENV_FILE — set it, restart 'start', then retry."

	if ! webhook_reachable; then
		fatal "Webhook not reachable at $WEBHOOK_URL — run 'bin/payments-dev.sh start' first."
	fi

	local ts id body sig resp code resp_body
	ts="$(node -e 'process.stdout.write(String(Date.now()))')"
	id="evt_local_${ts}_${RANDOM}"
	# Build the body via node (env-var passthrough = no quoting hazards).
	body="$(RC_TYPE="$etype" RC_ID="$id" RC_USER="$user" RC_PRODUCT="$product" RC_TS="$ts" node -e '
		const e = process.env;
		process.stdout.write(JSON.stringify({ event: {
			type: e.RC_TYPE,
			id: e.RC_ID,
			app_user_id: e.RC_USER,
			product_id: e.RC_PRODUCT,
			event_timestamp_ms: Number(e.RC_TS),
		}}));
	')"
	# HMAC-SHA256, lowercase hex — must match _shared/webhook_security.ts hmacHex.
	sig="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$secret" | awk '{print $NF}')"

	step "Replaying signed RevenueCat $etype"
	dim "→ $WEBHOOK_URL"
	dim "app_user_id=$user  product_id=$product  id=$id"
	resp="$(curl -sS -X POST "$WEBHOOK_URL" \
		-H 'content-type: application/json' \
		-H "x-revenuecat-hmac: $sig" \
		--data-raw "$body" \
		-w $'\n%{http_code}')"
	code="${resp##*$'\n'}"
	resp_body="${resp%$'\n'*}"
	log "response: $resp_body"
	if [[ "$code" == "200" ]]; then
		ok "HTTP 200 — handler accepted the event"
		dim "Verify the tier flip:"
		dim "  pnpm dev:db:psql -c \"select id, subscription_tier, billing_issue_at from user_profiles where id='$user';\""
	else
		err "HTTP $code"
		dim "503 = secret unset · 401 = signature/secret mismatch · 400 = stale/invalid event · 404 = not serving"
		return 1
	fi
}

cmd_status() {
	step "payments dev status"
	if docker info >/dev/null 2>&1; then ok "docker running"; else err "docker not running"; fi
	if supabase_running; then ok "supabase stack up"; else warn "supabase stack down (pnpm dev:payments, or pnpm dev:db:up)"; fi
	if webhook_reachable; then ok "webhook reachable: $WEBHOOK_URL"; else warn "webhook not reachable (functions serve not running with --env-file)"; fi
	if command -v stripe >/dev/null 2>&1; then ok "stripe CLI: $(stripe --version 2>/dev/null | head -1)"; else warn "stripe CLI not installed (brew install stripe/stripe-cli/stripe)"; fi
	local secret; secret="$(read_secret)"
	if [[ -n "$secret" ]]; then ok "REVENUECAT_WEBHOOK_SECRET is set in .env.local"; else warn "REVENUECAT_WEBHOOK_SECRET empty in .env.local"; fi
}

cmd_stop() {
	step "stopping functions serve"
	if pgrep -f 'supabase functions serve' >/dev/null 2>&1; then
		pkill -f 'supabase functions serve' && ok "stopped functions serve" || warn "could not stop functions serve"
	else
		log "no 'supabase functions serve' process found"
	fi
	dim "The Supabase DB stack is left running — stop it with: pnpm dev:db:down"
}

usage() {
	cat <<EOF
${C_BOLD}payments-dev.sh${C_RESET} — local Stripe + RevenueCat testing loop

  ${C_BOLD}start${C_RESET}                          boot Supabase + functions serve (.env.local) + stripe listen
  ${C_BOLD}replay${C_RESET} [TYPE] [PRODUCT] [UUID] POST a signed RevenueCat event to the local handler
  ${C_BOLD}status${C_RESET}                         show what's running / configured
  ${C_BOLD}stop${C_RESET}                           stop the functions-serve process (DB stays up)
  ${C_BOLD}help${C_RESET}                           this message

replay defaults: TYPE=INITIAL_PURCHASE  PRODUCT=pro_monthly  UUID=<seed user>
  examples:
    bin/payments-dev.sh replay                          # seed user -> pro
    bin/payments-dev.sh replay RENEWAL                  # renewal (clears billing flag)
    bin/payments-dev.sh replay EXPIRATION               # downgrade -> free
    bin/payments-dev.sh replay INITIAL_PURCHASE pro_lifetime   # -> lifetime
  via pnpm (note the --):
    pnpm dev:payments:replay -- EXPIRATION

Prereqs: Docker running · supabase CLI · stripe CLI (stripe login) · node/openssl/curl
Set REVENUECAT_WEBHOOK_SECRET in apps/backend/.env.local to any value first.
EOF
}

# ---- dispatch -------------------------------------------------------------

case "${1:-help}" in
	start|listen) shift; cmd_start "$@" ;;
	replay)       shift; cmd_replay "$@" ;;
	status)       shift; cmd_status "$@" ;;
	stop)         shift; cmd_stop "$@" ;;
	help|-h|--help) usage ;;
	*) err "unknown subcommand: $1"; echo; usage; exit 1 ;;
esac
