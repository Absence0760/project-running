#!/usr/bin/env bash
#
# key-rotate.sh — re-encrypt an env's secrets file under the current
# KMS key. The encrypted file lives in the PRIVATE estate repo
# (../infra-secrets/running/<env>.sops.yaml), NOT this public repo.
#
# Use case: you've changed the KMS key (via terraform — destroyed +
# recreated, or moved to a different key in the estate `.sops.yaml`),
# and the encrypted file still has the OLD key in its sops metadata.
# sops auto-decrypts against whatever key it was encrypted with, so
# the file keeps WORKING — but the next operator with access only to
# the new key can't decrypt it. This script reads the file with the
# old key, re-encrypts under the new key recorded in the estate
# `.sops.yaml`. Remember to commit the re-encrypted file in the
# private estate repo afterward.
#
# Note on AWS-native KMS rotation: enabling automatic key rotation
# (`aws kms enable-key-rotation`) does NOT require this script —
# rotation under the same key alias is transparent to sops. Use
# this script only when the *key itself* (not just the key material)
# changes.
#
# Usage:
#   bin/key-rotate.sh <env>
#   bin/key-rotate.sh preview
#   bin/key-rotate.sh prod

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [[ $# -ne 1 ]]; then
	cat >&2 <<EOF
Usage: bin/key-rotate.sh <env>
  env  preview | prod
EOF
	exit 2
fi

ENV_NAME="$1"
case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME" ;;
esac

need_cmd sops
need_cmd grep
need_aws_auth

# Secrets live in the PRIVATE estate repo, not this public one.
INFRA_SECRETS_DIR="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
SECRETS_FILE="$INFRA_SECRETS_DIR/running/$ENV_NAME.sops.yaml"
SOPS_CONFIG="$INFRA_SECRETS_DIR/.sops.yaml"

if [[ ! -f "$SECRETS_FILE" ]]; then
	fatal "$SECRETS_FILE missing — nothing to rotate (estate repo at $INFRA_SECRETS_DIR; set INFRA_SECRETS_DIR if elsewhere)"
fi

step "Current sops metadata for $ENV_NAME"
# sops writes the encryption metadata (KMS ARN, lastmodified, mac) as
# *plaintext* alongside the encrypted payload. Read it directly with
# grep — `sops --decrypt --extract` doesn't apply to metadata, only
# to the encrypted body.
current_arn="$(grep -oE 'arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+' "$SECRETS_FILE" | head -1)"
if [[ -n "$current_arn" ]]; then
	ok "Encrypted under: $current_arn"
else
	warn "Couldn't read current KMS ARN from $SECRETS_FILE — proceeding anyway"
fi

# Read the target ARN from .sops.yaml — that's the source of truth
# for "the key we want this file under".
case "$ENV_NAME" in
	preview) target_arn_line="$(grep -A1 'preview/secrets' "$SOPS_CONFIG" | grep 'kms:' || true)" ;;
	prod)    target_arn_line="$(grep -A1 'prod/secrets'    "$SOPS_CONFIG" | grep 'kms:' || true)" ;;
esac
# Pull out exactly the ARN shape — survives YAML inline comments,
# quotes, and trailing whitespace that a permissive regex wouldn't.
target_arn="$(echo "$target_arn_line" | grep -oE 'arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+' | head -1 || true)"
# Fall back to the placeholder text when no ARN matches, so the next
# guard can fail with a useful "still has placeholder" message.
if [[ -z "$target_arn" ]] && echo "$target_arn_line" | grep -qE 'REPLACE_(PROD|PREVIEW)_KMS_ARN'; then
	target_arn="REPLACE_$(echo "$ENV_NAME" | tr '[:lower:]' '[:upper:]')_KMS_ARN"
fi
if [[ "$target_arn" == REPLACE_* ]] || [[ -z "$target_arn" ]]; then
	fatal "$SOPS_CONFIG has unresolved KMS placeholder for $ENV_NAME — run bin/sops-init.sh first"
fi
ok "Target key in .sops.yaml: $target_arn"

if [[ "$current_arn" == "$target_arn" ]]; then
	ok "Already encrypted under the target key — nothing to rotate"
	exit 0
fi

step "Re-encrypting"
log "Running 'sops updatekeys' against $SECRETS_FILE"
log "(reads with old key, re-writes under the new key from .sops.yaml)"
sops updatekeys --config "$SOPS_CONFIG" "$SECRETS_FILE"
ok "Rotation complete"

step "Verify"
# Explicit decrypt round-trip — fail loudly if rotation broke decrypt.
if sops -d "$SECRETS_FILE" >/dev/null 2>&1; then
	ok "decrypts cleanly under the new key"
else
	fatal "Re-encrypted file does NOT decrypt — rotation may have left it inconsistent. Investigate before re-applying terraform."
fi

step "Commit the re-encrypted file (PRIVATE estate repo)"
dim "  (cd $INFRA_SECRETS_DIR && git commit -am 'running: rotate $ENV_NAME key')"

step "Push to Lambda"
log "The Lambda still has env vars from the old apply. Re-apply to push:"
dim "  cd infra/envs/$ENV_NAME && terraform apply"
