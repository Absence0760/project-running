#!/usr/bin/env bash
#
# disaster-recovery.sh — interactive runbook for rebuilding the AWS
# stack from scratch. Walks you through the same phases documented in
# infra/README.md and apps/web/deployment.md, in order, with a
# pause + checklist between each.
#
# This is NOT a fully automated rebuild. Some phases (DNS NS records
# at your registrar, GitHub Secrets paste-in) require human action
# you can't script away. This file's job is to keep you on the path
# and tell you what comes next at every step — the stress-free
# version of the README.
#
# Usage:
#   bin/disaster-recovery.sh                # interactive
#   bin/disaster-recovery.sh --status       # just show current phase

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

STATUS_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--status) STATUS_ONLY=1 ;;
		*) fatal "Unknown flag: $arg" ;;
	esac
done

# ----------------------------------------------------------------------------
# Probe what's already done so we can pick up mid-rebuild.
# ----------------------------------------------------------------------------

probe_phase_done() {
	local phase="$1"
	case "$phase" in
		2a)
			# State bucket exists?
			aws s3api head-bucket --bucket threkir-tfstate >/dev/null 2>&1
			;;
		2b)
			# DNS hosted zone exists with one of our nameservers?
			[[ -d "$REPO_ROOT/infra/dns/.terraform" ]] && \
				( cd "$REPO_ROOT/infra/dns" && terraform output -raw zone_id >/dev/null 2>&1 )
			;;
		2c)
			# OIDC provider + roles exist?
			[[ -d "$REPO_ROOT/infra/github-oidc/.terraform" ]] && \
				( cd "$REPO_ROOT/infra/github-oidc" && terraform output -raw deploy_role_arn_preview >/dev/null 2>&1 )
			;;
		2d)
			# preview env applied?
			[[ -d "$REPO_ROOT/infra/envs/preview/.terraform" ]] && \
				( cd "$REPO_ROOT/infra/envs/preview" && terraform output -raw cloudfront_domain_name >/dev/null 2>&1 )
			;;
		3a)
			# Are the GitHub Actions secrets set?
			gh secret list 2>/dev/null | grep -q PUBLIC_SUPABASE_URL
			;;
		3b)
			# Three conditions for "Phase 3b done":
			#   (1) the secrets file exists (in the PRIVATE estate repo),
			#   (2) the estate .sops.yaml has no unresolved running/* KMS
			#       placeholders, and
			#   (3) the secrets file decrypts AND its contents are not
			#       just the seed placeholder ("replace-me").
			# (3) catches the false-positive where sops-init ran but
			# the operator never edited in real values.
			local infra_secrets_dir="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
			local secrets_file="$infra_secrets_dir/running/preview.sops.yaml"
			[[ -f "$secrets_file" ]] || return 1
			grep -qE 'KMS_RUNNING_(PROD|PREVIEW)_ARN_PLACEHOLDER' "$infra_secrets_dir/.sops.yaml" && return 1
			# Decrypt + check for the seed placeholder.
			local decrypted
			decrypted="$(sops --decrypt "$secrets_file" 2>/dev/null || true)"
			[[ -n "$decrypted" ]] || return 1
			# If every value is `replace-me`, treat as not-done.
			if echo "$decrypted" | grep -qE '^[A-Z_][A-Z0-9_]*:\s*replace-me\s*$' \
				&& ! echo "$decrypted" | grep -qvE '^[A-Z_][A-Z0-9_]*:\s*replace-me\s*$|^\s*$|^#'; then
				return 1
			fi
			return 0
			;;
	esac
}

print_status() {
	step "Disaster-recovery status"
	# Without AWS auth, the 2a / 2d / 3b probes fail silently and would
	# all report "pending" even when they're done — misleading. Check
	# upfront so the user knows when probes can't actually tell.
	local aws_ok=1
	if ! aws sts get-caller-identity >/dev/null 2>&1; then
		aws_ok=0
		warn "AWS auth missing — Phase 2a / 2d / 3b probes can't verify state."
		dim "  Run 'aws sso login --profile \${AWS_PROFILE:-running}' for accurate status."
	fi
	for phase in 2a 2b 2c 2d 3a 3b; do
		if probe_phase_done "$phase"; then
			ok "Phase $phase done"
		else
			if (( aws_ok == 0 )) && [[ "$phase" =~ ^(2a|2d|3b)$ ]]; then
				dim "Phase $phase ? (cannot verify without AWS auth)"
			else
				warn "Phase $phase pending"
			fi
		fi
	done
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

pause_or_exit() {
	# Keeps the operator in control between phases.
	if confirm "Continue to next phase?"; then return 0; fi
	warn "Stopped at user request. Re-run this script later to continue."
	exit 0
}

# ----------------------------------------------------------------------------
# Status-only mode
# ----------------------------------------------------------------------------

if [[ $STATUS_ONLY -eq 1 ]]; then
	print_status
	exit 0
fi

# ----------------------------------------------------------------------------
# Walkthrough
# ----------------------------------------------------------------------------

step "Disaster recovery — rebuild from scratch"
log "This walks you through Phases 2a→3b in order. It runs read-only"
log "probes between phases to detect what's already been done; you can"
log "stop and resume at any step."

print_status
echo
if ! confirm "Begin?"; then exit 0; fi

# ── Phase 2a — Bootstrap state bucket ──
if probe_phase_done 2a; then
	ok "Phase 2a (state bucket) already complete — skipping"
else
	step "Phase 2a — bootstrap state bucket"
	log "Will run: cd infra/bootstrap && terraform init && terraform apply -var state_bucket_name=threkir-tfstate"
	if confirm "Proceed with Phase 2a?"; then
		"$REPO_ROOT/bin/aws-preflight.sh" || fatal "Preflight failed"
		(
			cd "$REPO_ROOT/infra/bootstrap"
			terraform init -input=false
			terraform apply -var "state_bucket_name=threkir-tfstate"
		)
		ok "Phase 2a complete"
	fi
fi
pause_or_exit

# ── Phase 2b — DNS ──
if probe_phase_done 2b; then
	ok "Phase 2b (DNS) already complete — skipping"
else
	step "Phase 2b — Route 53 + ACM cert"
	warn "AFTER apply, you must paste the four NS records at your domain registrar."
	warn "ACM will not validate (and CloudFront cert will not issue) until DNS resolves."
	if confirm "Proceed with Phase 2b?"; then
		(
			cd "$REPO_ROOT/infra/dns"
			terraform init -input=false
			terraform apply
		)
		log ""
		log "Now copy the NS records from terraform output:"
		dim "  cd infra/dns && terraform output -json zone_name_servers | jq -r '.[]'"
		log ""
		log "Paste those four values at your domain registrar (Porkbun/Namecheap/etc.) as the apex's NS records."
		log "ACM cert validation can take 5–30 minutes after the NS update propagates."
		read -rp "Press Enter once you've pasted them and waited for the cert to issue. " _
	fi
fi
pause_or_exit

# ── Phase 2c — GitHub OIDC ──
if probe_phase_done 2c; then
	ok "Phase 2c (OIDC) already complete — skipping"
else
	step "Phase 2c — GitHub OIDC + per-env deploy roles"
	log "After apply, copy the role ARNs into GitHub Actions secrets:"
	log "  AWS_DEPLOY_ROLE_ARN_PREVIEW = …role/runonward-web-preview-deploy"
	log "  AWS_DEPLOY_ROLE_ARN_PROD    = …role/runonward-web-prod-deploy"
	if confirm "Proceed with Phase 2c?"; then
		(
			cd "$REPO_ROOT/infra/github-oidc"
			terraform init -input=false
			terraform apply
			echo
			echo "Role ARNs (paste these into GitHub Actions secrets):"
			echo "  AWS_DEPLOY_ROLE_ARN_PREVIEW=$(terraform output -raw deploy_role_arn_preview)"
			echo "  AWS_DEPLOY_ROLE_ARN_PROD=$(terraform output -raw deploy_role_arn_prod)"
		)
		read -rp "Press Enter once both ARNs are saved as GitHub secrets. " _
	fi
fi
pause_or_exit

# ── Phase 2d — Preview env stack ──
if probe_phase_done 2d; then
	ok "Phase 2d (preview env) already complete — skipping"
else
	step "Phase 2d — apply infra/envs/preview"
	log "Creates S3 + CloudFront + Lambda + KMS for preview."
	log "Make sure infra/envs/preview/terraform.tfvars exists; copy from .example if needed."
	if confirm "Proceed with Phase 2d?"; then
		if [[ ! -f "$REPO_ROOT/infra/envs/preview/terraform.tfvars" ]]; then
			warn "infra/envs/preview/terraform.tfvars missing"
			cp "$REPO_ROOT/infra/envs/preview/terraform.tfvars.example" \
			   "$REPO_ROOT/infra/envs/preview/terraform.tfvars"
			log "Copied from .example. Edit it now to set your apex_domain etc., then re-run this script."
			exit 0
		fi
		(
			cd "$REPO_ROOT/infra/envs/preview"
			terraform init -input=false
			terraform apply
		)
		ok "Phase 2d complete"
	fi
fi
pause_or_exit

# ── Phase 3a — GitHub build secrets ──
if probe_phase_done 3a; then
	ok "Phase 3a (GHA build secrets) already complete — skipping"
else
	step "Phase 3a — GitHub Actions build-input secrets"
	log "Set these in GitHub → Settings → Secrets and variables → Actions:"
	dim "  PUBLIC_SUPABASE_URL"
	dim "  PUBLIC_SUPABASE_ANON_KEY"
	dim "  PUBLIC_MAPTILER_KEY"
	dim "  PUBLIC_REVENUECAT_WEB_CHECKOUT_URL  (if RevenueCat is wired)"
	dim "  PUBLIC_REVENUECAT_WEB_PORTAL_URL    (optional)"
	dim "  PUBLIC_SENTRY_DSN              (if Sentry is wired)"
	read -rp "Press Enter once the secrets are saved. " _
fi
pause_or_exit

# ── Phase 3b — sops + Lambda runtime secrets ──
if probe_phase_done 3b; then
	ok "Phase 3b (sops Lambda secrets) already complete — skipping"
else
	step "Phase 3b — sops-encrypt Lambda runtime secrets"
	log "Resolves the running/preview KMS ARN in the estate ../infra-secrets/.sops.yaml,"
	log "seeds an encrypted ../infra-secrets/running/preview.sops.yaml, and reapplies"
	log "preview so the Lambda picks up the env vars."
	if confirm "Run bin/sops-init.sh preview?"; then
		"$REPO_ROOT/bin/sops-init.sh" preview
	fi
	log ""
	log "Now edit the secrets file (in the PRIVATE estate repo) and put the real Anthropic key in:"
	dim "  sops ${INFRA_SECRETS_DIR:-../infra-secrets}/running/preview.sops.yaml"
	read -rp "Press Enter once you've added the real Anthropic API key. " _
	log "Re-applying preview so Lambda picks up the new env vars:"
	(
		cd "$REPO_ROOT/infra/envs/preview"
		terraform apply
	)
	ok "Phase 3b complete"
fi

# ── Verification ──
step "Final verification"
"$REPO_ROOT/bin/preview-status.sh" preview
