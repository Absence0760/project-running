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

# Secrets live in the PRIVATE estate repo, not this public one. The slug is
# the estate subdirectory, and it is what sops-init.sh and secret-set.sh build
# their paths from too.
PROJECT_SLUG="running"
INFRA_SECRETS_DIR="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
SECRETS_FILE="$INFRA_SECRETS_DIR/$PROJECT_SLUG/$ENV_NAME.sops.yaml"
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
#
# The estate config routes by the file's OWN path, so the rule to read is the
# one whose path_regex names this file. Anchoring on anything else is how this
# went stale: the anchors here were `<env>/secrets` and the placeholder
# `REPLACE_<ENV>_KMS_ARN`, both from the layout before the secrets moved into
# the estate repo. Neither string exists in the estate .sops.yaml, so BOTH envs
# matched nothing and this script died claiming an unresolved placeholder — on
# prod, whose key is fully wired — and sent the operator to re-run
# sops-init.sh, which would tell them it is already resolved.
#
# The dots are optionally-backslashed because the VALUE of path_regex is itself
# a regex: the estate file spells the rule `^running/prod\.sops\.yaml$`, so an
# anchor whose `\.` means "a literal dot" matches nothing at all. That is the
# second way this line can silently find no rule, and it fails identically to
# the first.
rule_anchor="$PROJECT_SLUG/$ENV_NAME"'\\?\.sops\\?\.yaml'
target_arn_line="$(grep -A1 -E "path_regex:.*$rule_anchor" "$SOPS_CONFIG" | grep 'kms:' || true)"
# Pull out exactly the ARN shape — survives YAML inline comments,
# quotes, and trailing whitespace that a permissive regex wouldn't.
target_arn="$(echo "$target_arn_line" | grep -oE 'arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+' | head -1 || true)"
# The placeholder sops-init.sh writes, derived the same way it derives it —
# `KMS_<SLUG>_<ENV>_ARN_PLACEHOLDER` — so the two cannot drift apart again.
placeholder="KMS_$(echo "${PROJECT_SLUG}_${ENV_NAME}" | tr '[:lower:]-' '[:upper:]_')_ARN_PLACEHOLDER"
# Three different failures, three different sentences. Collapsing them is what
# made the stale anchor above look like an un-run sops-init.
if [[ -z "$target_arn" ]]; then
	if [[ -z "$target_arn_line" ]]; then
		fatal "no creation rule in $SOPS_CONFIG matches $PROJECT_SLUG/$ENV_NAME.sops.yaml — run bin/sops-init.sh $ENV_NAME first"
	fi
	if echo "$target_arn_line" | grep -qF "$placeholder"; then
		fatal "$SOPS_CONFIG still has $placeholder — run bin/sops-init.sh $ENV_NAME first"
	fi
	fatal "could not read a KMS ARN out of the $PROJECT_SLUG/$ENV_NAME rule in $SOPS_CONFIG"
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
