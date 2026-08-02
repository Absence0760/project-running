#!/usr/bin/env bash
#
# lambda-alias-sync.sh — repoint each web Lambda's `live` alias to its
# newest published version.
#
# Why this exists: the `live` aliases are CI-owned (Terraform holds
# `ignore_changes = [function_version]`; release-web.yml repoints them
# on every code deploy), but an env-only `terraform apply` — a secret
# rotation, a new engine URL — publishes a fresh version and leaves the
# alias behind. The Function URLs target the alias, so the rotated env
# never reaches the serving path: the alias keeps serving the old
# version's frozen env snapshot (issue #590 defect 2 — the 2026-07-21
# key swap published v12 while `live` kept serving v11's disabled key).
# Run this after any env-only apply, or cut a release instead.
#
# Usage:
#   bin/lambda-alias-sync.sh                    # preview, prompt per repoint
#   bin/lambda-alias-sync.sh prod
#   bin/lambda-alias-sync.sh prod --dry-run     # report drift, change nothing
#   bin/lambda-alias-sync.sh prod --auto-approve

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENV_NAME="${1:-preview}"
case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac
shift || true

DRY_RUN=0
AUTO=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run)      DRY_RUN=1; shift ;;
		--auto-approve) AUTO=1; shift ;;
		*)              fatal "Unknown flag: $1" ;;
	esac
done

need_cmd aws
need_aws_auth

# Kept in lockstep with the `aws_lambda_alias` set in
# infra/modules/web-stack/main.tf and the per-function deploy steps in
# .github/workflows/release-web.yml by scripts/check_lambda_alias_sync.mjs,
# which parses all three and fails CI on disagreement in either direction.
# Terraform is the source of truth; add the Lambda there first.
FUNCTIONS=(coach share-run share-route share-recap share-badge share-entity generate-route osrm-proxy)

DRIFTED=0
SKIPPED=0
for fn in "${FUNCTIONS[@]}"; do
	NAME="threkir-web-${ENV_NAME}-${fn}"
	step "$NAME"

	NEWEST=$(aws lambda list-versions-by-function \
		--function-name "$NAME" \
		--query 'Versions[?Version!=`$LATEST`].[Version]' \
		--output text | sort -n | tail -1)
	if [[ -z "$NEWEST" || "$NEWEST" == "None" ]]; then
		warn "no published versions — skipping (function not deployed yet?)"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi

	# `|| true` because a bare command substitution carries its own exit
	# status into the assignment, and `set -e` then kills the whole sweep —
	# so one function whose `live` alias does not exist yet (deployed, but
	# no terraform apply) would silently take every function after it in the
	# array down with it, with nothing in the output saying so. The
	# published-versions branch above already treats "not ready" as a skip;
	# these two disagreeing about it is what made the failure invisible.
	CURRENT=$(aws lambda get-alias \
		--function-name "$NAME" \
		--name live \
		--query FunctionVersion \
		--output text 2>/dev/null || true)
	if [[ -z "$CURRENT" || "$CURRENT" == "None" ]]; then
		warn "no live alias — skipping (terraform apply not run for this function?)"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi

	if [[ "$CURRENT" == "$NEWEST" ]]; then
		ok "live already at v$CURRENT"
		continue
	fi

	DRIFTED=1
	warn "live at v$CURRENT, newest published is v$NEWEST"
	if [[ $DRY_RUN -eq 1 ]]; then
		continue
	fi
	if [[ $AUTO -ne 1 ]] && ! confirm "Repoint ${NAME}:live v$CURRENT -> v$NEWEST?"; then
		log "skipped"
		continue
	fi
	aws lambda update-alias \
		--function-name "$NAME" \
		--name live \
		--function-version "$NEWEST" >/dev/null
	ok "live -> v$NEWEST"
done

if [[ $DRIFTED -eq 0 && $SKIPPED -eq 0 ]]; then
	step "All ${#FUNCTIONS[@]} aliases already current for $ENV_NAME"
elif [[ $DRIFTED -eq 0 ]]; then
	step "$((${#FUNCTIONS[@]} - SKIPPED)) alias(es) current for $ENV_NAME, $SKIPPED skipped"
elif [[ $DRY_RUN -eq 1 ]]; then
	step "Dry run — drift reported above, nothing changed"
fi
if [[ $SKIPPED -gt 0 ]]; then
	# Named explicitly: a skipped function is one this run did NOT verify, and
	# a sweep that checked 6 of 8 must not read like a clean sweep.
	warn "$SKIPPED function(s) skipped — not verified this run"
fi
