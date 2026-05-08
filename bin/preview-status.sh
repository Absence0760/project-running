#!/usr/bin/env bash
#
# preview-status.sh — one-shot health check of a deployed env.
#
# Reads the env's terraform outputs to find the CloudFront domain and
# Lambda function name, then probes:
#
#   1. HTTPS / on the public domain      → expect 200
#   2. /api/coach with no auth          → expect 401
#   3. CloudFront distribution status   → expect Deployed
#   4. Lambda recent log lines           → just dump the last 10
#
# Output is one block per check, with PASS / WARN / FAIL labels.
# Exits 0 if all PASS, 1 if any FAIL.
#
# Usage:
#   bin/preview-status.sh                # default env: preview
#   bin/preview-status.sh prod
#   bin/preview-status.sh preview --logs 50

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENV_NAME="${1:-preview}"
LOG_LINES=10
case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac

shift || true
while [[ $# -gt 0 ]]; do
	case "$1" in
		--logs) LOG_LINES="$2"; shift 2 ;;
		*) fatal "Unknown flag: $1" ;;
	esac
done

ENV_DIR="$REPO_ROOT/infra/envs/$ENV_NAME"
if [[ ! -d "$ENV_DIR" ]]; then
	fatal "$ENV_DIR does not exist — pick a different env or check the path"
fi
FAILS=0
WARNS=0

read_tf_output() {
	local key="$1"
	pushd "$ENV_DIR" >/dev/null
	terraform output -raw "$key" 2>/dev/null || true
	popd >/dev/null
}

step "Reading terraform outputs ($ENV_NAME)"
DOMAIN_NAME="$(read_tf_output cloudfront_domain_name)"
LAMBDA_NAME="$(read_tf_output lambda_function_name)"
DIST_ID="$(read_tf_output cloudfront_distribution_id)"

if [[ -z "$DOMAIN_NAME" ]]; then
	fatal "No terraform output for cloudfront_domain_name in $ENV_DIR — is the env applied?"
fi
ok "CloudFront domain: $DOMAIN_NAME"
ok "Lambda function:   $LAMBDA_NAME"
ok "Distribution ID:   $DIST_ID"

# We have the cloudfront.net hostname. Construct the public hostname
# from the same convention release-web.yml uses (preview.<apex> /
# <apex> + www.<apex>). Fall back to *.cloudfront.net if we can't
# read the apex.
# Anchor the regex to `apex_domain` followed by `=` so we don't match
# `apex_domain_alt` or any other variable that starts with the same prefix.
APEX="$(grep -E '^apex_domain[[:space:]]*=' "$ENV_DIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
if [[ -n "$APEX" ]]; then
	if [[ "$ENV_NAME" == "preview" ]]; then
		PUBLIC_HOST="preview.$APEX"
	else
		PUBLIC_HOST="$APEX"
	fi
	ok "Public hostname:   $PUBLIC_HOST"
else
	PUBLIC_HOST="$DOMAIN_NAME"
	warn "Couldn't read apex_domain from $ENV_DIR/terraform.tfvars — using cloudfront.net hostname"
fi

step "1/4 — HTTPS / responds 200"
# 30s budget — CloudFront edge cache miss + S3 origin can take a while
# on first hit after deploy.
status="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 "https://$PUBLIC_HOST/" || echo "000")"
case "$status" in
	200) ok "PASS — HTTP $status" ;;
	000) err "FAIL — connection failed (DNS, CloudFront, or TLS)"; FAILS=$((FAILS + 1)) ;;
	*)   err "FAIL — HTTP $status (expected 200)"; FAILS=$((FAILS + 1)) ;;
esac

step "2/4 — /api/coach gates anon access"
# Should return 401 (anon) or 503 (unconfigured) — never 200, never 5xx
# from the runtime. 30s budget — Lambda cold start can exceed 10s.
status="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 \
	-X POST -H "content-type: application/json" -d '{"message":"x"}' \
	"https://$PUBLIC_HOST/api/coach" || echo "000")"
case "$status" in
	401) ok "PASS — HTTP $status (anon properly rejected)" ;;
	503) warn "WARN — HTTP 503 (Coach not configured: ANTHROPIC_API_KEY unset on Lambda — Phase 3b)"; WARNS=$((WARNS + 1)) ;;
	000) err "FAIL — connection failed"; FAILS=$((FAILS + 1)) ;;
	*)   err "FAIL — HTTP $status (expected 401 or 503)"; FAILS=$((FAILS + 1)) ;;
esac

step "3/4 — CloudFront distribution Deployed"
if [[ -n "$DIST_ID" ]]; then
	dist_status="$(aws cloudfront get-distribution --id "$DIST_ID" \
		--query 'Distribution.Status' --output text 2>/dev/null || echo "unknown")"
	if [[ "$dist_status" == "Deployed" ]]; then
		ok "PASS — $dist_status"
	else
		warn "WARN — Status: $dist_status (CloudFront propagation can take 5–15 min after a change)"
		WARNS=$((WARNS + 1))
	fi
else
	warn "WARN — no distribution_id from terraform output"
	WARNS=$((WARNS + 1))
fi

step "4/4 — Recent Lambda logs ($LAMBDA_NAME)"
log_group="/aws/lambda/$LAMBDA_NAME"
if aws logs describe-log-groups --log-group-name-prefix "$log_group" \
		--query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
	dim "Last $LOG_LINES log events:"
	aws logs tail "$log_group" --since 1h --format short 2>/dev/null \
		| tail -n "$LOG_LINES" \
		| sed 's/^/      /' || warn "  (no recent log events)"
else
	warn "WARN — log group $log_group does not exist yet (Lambda may not have been invoked)"
fi

step "Summary"
if (( FAILS > 0 )); then
	err "$FAILS check(s) FAILED, $WARNS warning(s) — preview is degraded"
	exit 1
fi
if (( WARNS > 0 )); then
	warn "$WARNS warning(s) — preview is up but not fully configured"
	exit 0
fi
ok "All checks passed — preview is healthy"
