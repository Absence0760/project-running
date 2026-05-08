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

if [[ $SKIP_PREFLIGHT -eq 0 ]]; then
	step "Preflight"
	# Capture output in a tmpfile so a hard-fail can be re-displayed
	# without re-running the AWS API calls. Trap cleans up on exit.
	preflight_log="$(mktemp)"
	trap 'rm -f "$preflight_log"' EXIT
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
	if [[ $# -gt 0 && "$1" == "--" ]]; then
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
	log "Resolve sops placeholders against the new KMS keys:"
	dim "  bin/sops-init.sh preview"
	log ""
	log "Verify the preview is healthy:"
	dim "  bin/preview-status.sh preview"
fi
ok "Done"
