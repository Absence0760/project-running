#!/usr/bin/env bash
#
# deploy-preview.sh — orchestrated apply of every Terraform stack
# needed for the preview env, in the right order, idempotently.
#
# Stack order (each depends on the previous one's state):
#   1. infra/bootstrap         (state bucket — once per account)
#   2. infra/dns               (Route 53 + ACM cert — once per apex)
#   3. infra/github-oidc       (deploy roles — once per account)
#   4. infra/envs/preview      (the actual web stack)
#
# For each stack: terraform init → plan → prompt → apply. Skips a
# stack if `terraform plan` shows no changes.
#
# Flags:
#   --plan          plan only, never apply (read-only)
#   --auto-approve  apply without prompting (CI-style)
#   --skip-preflight  skip aws-preflight.sh (don't unless you know why)
#
# Usage:
#   bin/deploy-preview.sh                 # interactive, full chain
#   bin/deploy-preview.sh --plan          # see what would change
#   bin/deploy-preview.sh --auto-approve  # for CI / batch runs

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PLAN_ONLY=0
AUTO_APPROVE=0
SKIP_PREFLIGHT=0

for arg in "$@"; do
	case "$arg" in
		--plan) PLAN_ONLY=1 ;;
		--auto-approve) AUTO_APPROVE=1 ;;
		--skip-preflight) SKIP_PREFLIGHT=1 ;;
		*) fatal "Unknown flag: $arg" ;;
	esac
done

preflight_log=""

# Single EXIT trap that cleans up everything we may have created:
#   - the preflight log tmpfile
#   - any per-stack .tfplan files (a mid-chain `terraform apply` failure
#     under set -e leaves these behind; harmless but clutter)
cleanup_on_exit() {
	[[ -n "$preflight_log" && -f "$preflight_log" ]] && rm -f "$preflight_log"
	for stack_dir in infra/bootstrap infra/dns infra/github-oidc infra/envs/preview; do
		rm -f "$REPO_ROOT/$stack_dir/.tfplan"
	done
}
trap cleanup_on_exit EXIT

if [[ $SKIP_PREFLIGHT -eq 0 ]]; then
	step "Preflight"
	# Capture output in a tmpfile so a hard-fail can be re-displayed
	# without re-running the AWS API calls.
	preflight_log="$(mktemp)"
	if "$REPO_ROOT/bin/aws-preflight.sh" >"$preflight_log" 2>&1; then
		ok "Preflight passed"
	else
		warn "Preflight surfaced issues:"
		cat "$preflight_log" >&2
		fatal "Preflight failed; fix issues above before applying."
	fi
fi

apply_stack() {
	# usage: apply_stack <label> <dir> [-- extra terraform args...]
	# After the optional `--` separator, every remaining arg is passed
	# verbatim to `terraform plan`. The array form preserves quoting
	# even when a value contains spaces.
	local label="$1" dir="$2"
	shift 2
	local -a extra_args=()
	# Defaults the unset case to '' so we don't rely on bash's [[ ]]
	# short-circuit semantics under `set -u` — safer across versions.
	if [[ "${1:-}" == "--" ]]; then
		shift
		extra_args=("$@")
	fi

	step "$label  ($dir)"
	pushd "$REPO_ROOT/$dir" >/dev/null

	if [[ ! -d .terraform ]]; then
		log "terraform init"
		terraform init -input=false
	fi

	# Generate a plan to a file so we apply exactly what we previewed.
	local plan_file=".tfplan"
	if terraform plan -input=false -detailed-exitcode -out="$plan_file" "${extra_args[@]}"; then
		ok "$label has no pending changes — skipping apply"
		rm -f "$plan_file"
		popd >/dev/null
		return 0
	fi
	# detailed-exitcode: 0 = no changes, 1 = error, 2 = changes.
	# `if terraform plan ...` swallows 1 and 2 alike. If we got here
	# the plan either errored or has changes — terraform's own output
	# distinguishes the two cleanly above this line.

	if [[ $PLAN_ONLY -eq 1 ]]; then
		ok "Plan saved to $dir/$plan_file (--plan, not applying)"
		popd >/dev/null
		return 0
	fi

	local proceed=0
	if [[ $AUTO_APPROVE -eq 1 ]]; then
		proceed=1
	else
		if confirm "Apply $label?"; then
			proceed=1
		fi
	fi

	if [[ $proceed -eq 1 ]]; then
		terraform apply -input=false "$plan_file"
		ok "$label applied"
	else
		warn "$label not applied — stopping the chain so later stacks don't run on stale state"
		popd >/dev/null
		exit 0
	fi

	rm -f "$plan_file"
	popd >/dev/null
}

# Bootstrap takes a -var; the rest read from terraform.tfvars or
# remote state. Args after `--` are passed verbatim to `terraform plan`.
apply_stack "Stack 1/4: bootstrap (state bucket)" "infra/bootstrap" -- -var "state_bucket_name=runonward-tfstate"
apply_stack "Stack 2/4: dns (Route 53 + ACM)"     "infra/dns"
apply_stack "Stack 3/4: github-oidc (deploy roles)" "infra/github-oidc"
apply_stack "Stack 4/4: envs/preview (S3 + CloudFront + Lambda + KMS)" "infra/envs/preview"

step "Post-apply"
if [[ $PLAN_ONLY -eq 0 ]]; then
	# Detect whether the coach secret is already wired. If the env's
	# secrets file exists in the estate repo, the operator has already
	# done phase 2 and this was just a re-apply — point them at the
	# health check. Otherwise walk them through wiring the secret.
	infra_secrets_dir="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
	secrets_file="$infra_secrets_dir/running/preview.sops.yaml"
	if [[ -f "$secrets_file" ]]; then
		ok "Secrets file present ($secrets_file) — the Lambda has the coach key."
		log "Verify the env is healthy (coach should answer 401, not 503):"
		dim "  bin/preview-status.sh preview"
	else
		warn "No coach secret wired yet — the Lambda is up but /api/coach returns 503."
		log "Phase 2 — wire the secret (it lives in the PRIVATE ../infra-secrets repo, never here):"
		if [[ ! -d "$infra_secrets_dir" ]]; then
			dim "  git clone git@github.com:Absence0760/infra-secrets.git ../infra-secrets   # clone the estate repo first"
		fi
		dim "  bin/sops-init.sh preview                                   # wire KMS ARN + seed running/preview.sops.yaml"
		dim "  echo -n \"sk-ant-…\" | bin/secret-set.sh preview ANTHROPIC_API_KEY   # real key via stdin"
		dim "  (cd $infra_secrets_dir && git commit -am 'running: preview secrets')  # commit in the PRIVATE repo"
		dim "  bin/deploy-preview.sh                                       # re-run: idempotent, wires the secret into the Lambda"
		dim "  bin/preview-status.sh preview                              # confirm coach now answers 401, not 503"
	fi
fi
ok "Done"
