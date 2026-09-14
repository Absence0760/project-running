#!/usr/bin/env bash
#
# sops-init.sh — resolves the placeholder KMS ARNs in the PRIVATE estate repo's
# `../infra-secrets/.sops.yaml` after `terraform apply` on the per-env web-stack
# creates the keys, and (optionally) seeds an empty `threkir/<env>.sops.yaml`
# there for any env that doesn't have one yet.
#
# Production secrets live in ../infra-secrets (Absence0760/infra-secrets), NOT in
# this PUBLIC repo — one subdir per project, named by ESTATE_SLUG in
# bin/lib/estate.sh. Set INFRA_SECRETS_DIR to override the default sibling-clone
# location.
#
# This script does NOT create KMS keys — that's done by
# `infra/modules/web-stack` on `terraform apply`. The script's only
# job is to bridge the gap between "terraform created the keys" and
# "sops can use them" — i.e., copy the ARNs from terraform outputs
# into the estate `.sops.yaml`.
#
# Idempotent: re-running detects already-resolved placeholders and
# already-seeded files, prints a "nothing to do" status, and exits 0.
#
# Usage:
#   bin/sops-init.sh                   # all envs that have terraform state
#   bin/sops-init.sh preview           # just preview
#   bin/sops-init.sh prod              # just prod
#   bin/sops-init.sh preview prod      # both, explicit
#
# Prereqs:
#   - sops, aws, jq, terraform on PATH
#   - aws sts get-caller-identity succeeds (i.e. SSO login active)
#   - `terraform apply` already ran on each env you want to bootstrap
#     so `terraform output -raw kms_key_arn` returns a value
#
# Recovery: if you blow away an env and recreate it, the new KMS ARN
# replaces the old one in `.sops.yaml`. Existing encrypted files
# decrypt against whatever key they were encrypted with (the metadata
# is in the file), so they keep working until you `sops updatekeys`
# them under the new key. Run that explicitly if you re-keyed.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/lib/estate.sh"

cd "$REPO_ROOT"

# ----------------------------------------------------------------------------
# Args
# ----------------------------------------------------------------------------

declare -a ENVS
if [[ $# -eq 0 ]]; then
	ENVS=(preview prod)
else
	ENVS=("$@")
fi

for e in "${ENVS[@]}"; do
	case "$e" in
		preview|prod) ;;
		*) fatal "Unknown env: $e (expected preview or prod)" ;;
	esac
done

# ----------------------------------------------------------------------------
# Prereqs
# ----------------------------------------------------------------------------

step "Checking prereqs"
for cmd in sops aws jq terraform; do
	need_cmd "$cmd"
	ok "$cmd installed"
done

need_aws_auth
ok "AWS auth OK ($(aws sts get-caller-identity --query Arn --output text))"

if [[ ! -d "$INFRA_SECRETS_DIR" ]]; then
	fatal "Estate secrets repo not found at $INFRA_SECRETS_DIR — clone Absence0760/infra-secrets as a sibling of this repo, or set INFRA_SECRETS_DIR."
fi
if [[ ! -f "$SOPS_CONFIG" ]]; then
	fatal "$SOPS_CONFIG missing — is $INFRA_SECRETS_DIR a checkout of the infra-secrets repo?"
fi

# ----------------------------------------------------------------------------
# Per-env: read ARN from terraform output, write it into the estate .sops.yaml
# rule that governs the env's secrets file, optionally seed that file.
# ----------------------------------------------------------------------------

env_dir_for() {
	echo "$REPO_ROOT/infra/envs/$1"
}

for env in "${ENVS[@]}"; do
	step "Bootstrapping env: $env"
	env_dir="$(env_dir_for "$env")"
	secrets_rel="$(estate_secrets_rel "$env")"
	secrets_file="$(estate_secrets_file "$env")"
	if ! current_kms="$(estate_rule_kms "$secrets_rel")"; then
		fatal "No creation rule in $SOPS_CONFIG governs $secrets_rel, so sops would refuse to encrypt it. Add one in the estate repo, or check ESTATE_SLUG in bin/lib/estate.sh against the estate's slot."
	fi

	# Read the KMS arn from terraform output. Fail loudly if the env
	# hasn't been applied yet — we deliberately don't try to apply on
	# the user's behalf (that has too much blast radius for an init
	# script).
	pushd "$env_dir" >/dev/null

	if ! terraform output -raw kms_key_arn >/dev/null 2>&1; then
		warn "terraform output is missing kms_key_arn for $env"
		warn "Run 'terraform init && terraform apply' in $env_dir first, then re-run this script."
		popd >/dev/null
		continue
	fi

	arn="$(terraform output -raw kms_key_arn)"
	popd >/dev/null

	# Sanity-check the ARN shape: must be `arn:aws:kms:<region>:<acct>:key/<uuid>`.
	if ! [[ "$arn" =~ ^arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+$ ]]; then
		fatal "$env: terraform returned an unexpected kms_key_arn: $arn"
	fi
	ok "$env KMS ARN: $arn"

	# Idempotent: a rule already carrying this ARN is left alone. One carrying a
	# DIFFERENT ARN means the env's key was recreated; existing ciphertext still
	# decrypts under the old key, so repoint the rule and send the operator to
	# key-rotate.sh to move that ciphertext across.
	if [[ "$current_kms" == "$arn" ]]; then
		ok "$secrets_rel rule already carries this ARN — skipping"
	else
		if is_kms_arn "$current_kms"; then
			warn "$secrets_rel rule carried a different key ($current_kms) — repointing it; run bin/key-rotate.sh $env afterwards"
		fi
		estate_set_rule_kms "$secrets_rel" "$arn" \
			|| fatal "Could not rewrite the kms value of the $secrets_rel rule in $SOPS_CONFIG — edit it by hand"
		ok "Wired $arn into the $secrets_rel rule in $SOPS_CONFIG"
	fi

	# Seed the secrets file if missing. Empty-but-encrypted is fine:
	# operators edit it with `sops $secrets_file` to add real values.
	mkdir -p "$ESTATE_SLOT_DIR"
	if [[ -f "$secrets_file" ]]; then
		ok "$secrets_file already exists — leaving it alone"
	else
		log "Seeding $secrets_file (encrypted, with a placeholder key)"
		# Use `sops --output` instead of shell redirect: the redirect
		# truncates the target file BEFORE sops runs, so a sops failure
		# (KMS auth, network) leaves an empty file that breaks the
		# idempotence check on re-run.
		# sops chooses the creation rule by the INPUT's name, and /dev/stdin
		# matches none, so name the file it is becoming. It has to be the full
		# path: sops strips the config's directory off it before matching, and
		# run from this repo a path relative to the estate root matched no rule
		# (measured, sops 3.12).
		printf 'ANTHROPIC_API_KEY: replace-me\n' \
			| sops --config "$SOPS_CONFIG" --input-type yaml --output-type yaml \
				--filename-override "$secrets_file" \
				--output "$secrets_file" --encrypt /dev/stdin
		# Verify the seed actually decrypts — catches a broken seed at
		# write time, not at first read.
		if ! sops --decrypt "$secrets_file" >/dev/null 2>&1; then
			rm -f "$secrets_file"
			fatal "Seed of $secrets_file failed to decrypt round-trip; removed. Investigate KMS auth + .sops.yaml routing."
		fi
		ok "Seeded $secrets_file"
	fi
done

# ----------------------------------------------------------------------------
# Final sanity check + next steps
# ----------------------------------------------------------------------------

step "Verifying the estate .sops.yaml is fully resolved for this project"
unresolved=0
for env in preview prod; do
	secrets_rel="$(estate_secrets_rel "$env")"
	if ! kms="$(estate_rule_kms "$secrets_rel")"; then
		warn "No creation rule in $SOPS_CONFIG governs $secrets_rel"
		unresolved=1
	elif ! is_kms_arn "$kms"; then
		warn "The $secrets_rel rule still holds $kms — $env isn't applied yet"
		unresolved=1
	fi
done
if (( unresolved )); then
	warn "Apply the missing env(s) and re-run this script."
	exit 0
fi
ok "Both $ESTATE_SLUG/ rules carry a KMS ARN"

step "Next steps (commit the encrypted file in the PRIVATE estate repo, never here)"
log "Edit secrets:    sops $ESTATE_SLOT_DIR/<env>.sops.yaml"
log "Re-apply env:    cd infra/envs/<env> && terraform apply"
log "Verify decrypt:  sops --decrypt $ESTATE_SLOT_DIR/<env>.sops.yaml"
log "Commit secrets:  (cd $INFRA_SECRETS_DIR && git add $ESTATE_SLUG .sops.yaml && git commit)"
log ""
log "On every key rotation:"
log "  sops updatekeys $ESTATE_SLOT_DIR/<env>.sops.yaml"
