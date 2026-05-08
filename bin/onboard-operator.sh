#!/usr/bin/env bash
#
# onboard-operator.sh — grant a second human (or role) access to the
# project's sops-encrypted secrets, by adding kms:Decrypt + kms:Encrypt
# to the per-env KMS key policy.
#
# Per the audit findings (sops vs meryl-green-designs comparison):
# project-running uses per-env KMS keys (one per `infra/envs/<env>`)
# rather than a single shared key. So onboarding is a per-env action.
#
# What this does:
#   1. Reads the current key policy via `aws kms get-key-policy`
#   2. Appends a statement granting Decrypt + Encrypt to <principal-arn>
#      (or skips if the principal is already in there)
#   3. Writes the updated policy back via `aws kms put-key-policy`
#
# What it does NOT do:
#   - Doesn't add the principal to the GitHub Actions deploy role
#   - Doesn't grant terraform-apply permissions (that's a separate IAM
#     decision — operators usually have AdministratorAccess via SSO)
#   - Doesn't `sops updatekeys` the encrypted file — IAM is the source
#     of truth, no per-recipient re-encryption is needed for KMS sops
#
# Caveat — IaC drift: this script mutates the KMS key policy via API,
# which means the next `terraform apply` on the env may revert the
# change unless the policy is recomputed by the module. Long-term, the
# right home for "additional principals" is a terraform variable on
# `infra/modules/web-stack`. Treat this script as a stopgap for
# urgent onboarding before that var lands.
#
# Usage:
#   bin/onboard-operator.sh <principal-arn> [env]
#
#   bin/onboard-operator.sh arn:aws:iam::123:user/jane preview
#   bin/onboard-operator.sh arn:aws:iam::123:role/Admin both

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [[ $# -lt 1 || $# -gt 2 ]]; then
	cat >&2 <<EOF
Usage: bin/onboard-operator.sh <principal-arn> [env]

  principal-arn  Full ARN of the IAM user, role, or assumed-role-session
                 to grant decrypt access to.
  env            preview | prod | both  (default: both)

Example:
  bin/onboard-operator.sh arn:aws:iam::123456789012:user/jane both
EOF
	exit 2
fi

PRINCIPAL_ARN="$1"
ENVS="${2:-both}"

case "$ENVS" in
	preview) ENV_LIST=("preview") ;;
	prod)    ENV_LIST=("prod") ;;
	both)    ENV_LIST=("preview" "prod") ;;
	*)       fatal "env must be preview, prod, or both — got '$ENVS'" ;;
esac

if [[ ! "$PRINCIPAL_ARN" =~ ^arn:aws:iam::[0-9]+:(user|role|assumed-role)/ ]]; then
	fatal "Doesn't look like an IAM principal ARN: $PRINCIPAL_ARN"
fi

need_cmd aws
need_cmd jq
need_aws_auth

for env_name in "${ENV_LIST[@]}"; do
	step "Onboarding $PRINCIPAL_ARN to $env_name KMS key"
	env_dir="$REPO_ROOT/infra/envs/$env_name"
	pushd "$env_dir" >/dev/null

	if ! arn="$(terraform output -raw kms_key_arn 2>/dev/null)"; then
		warn "$env_name: no kms_key_arn output — has 'terraform apply' run on $env_dir?"
		popd >/dev/null
		continue
	fi
	popd >/dev/null

	key_id="${arn##*/}"
	ok "$env_name KMS key: $key_id"

	current_policy="$(aws kms get-key-policy --key-id "$key_id" \
		--policy-name default --query Policy --output text)"

	# EXACT-match check on the principal — substring match would
	# false-positive when a longer name has the new principal as a
	# prefix (e.g. "JaneAdmin" already in the policy would block adding
	# "Jane"). The .Principal.AWS field can be a string OR an array,
	# so the jq normalises with `if type == "array" then .[] else . end`
	# before comparing.
	if echo "$current_policy" | jq -e --arg p "$PRINCIPAL_ARN" '
		[ .Statement[].Principal.AWS // empty
		  | if type == "array" then .[] else . end ]
		| any(. == $p)
	' >/dev/null; then
		ok "$PRINCIPAL_ARN already on $env_name key policy — skipping"
		continue
	fi

	# Sid must be unique within the policy and ≤ 128 chars (AWS limit).
	# Append a short hash of the ARN so two principals with similar
	# alphanumeric forms don't collide.
	sid_suffix="$(printf '%s' "$PRINCIPAL_ARN" | sha256sum | cut -c1-8)"
	new_policy="$(echo "$current_policy" | jq --arg p "$PRINCIPAL_ARN" --arg sfx "$sid_suffix" '
		.Statement += [{
			Sid: ("OperatorAccess-" + ($p | gsub("[^A-Za-z0-9]"; ""))[0:96] + "-" + $sfx),
			Effect: "Allow",
			Principal: { AWS: $p },
			Action: ["kms:Decrypt", "kms:Encrypt", "kms:DescribeKey"],
			Resource: "*"
		}]
	')"

	# Sanity check before pushing — must still be valid JSON.
	echo "$new_policy" | jq . >/dev/null

	if confirm "Apply updated policy to $env_name key?"; then
		aws kms put-key-policy --key-id "$key_id" --policy-name default \
			--policy "$new_policy"
		ok "$env_name policy updated"
	else
		warn "$env_name skipped (no confirmation)"
	fi
done

step "Next steps for $PRINCIPAL_ARN"
log "On their machine they need:"
dim "  - aws CLI v2 + sops"
dim "  - aws sso login as a profile that resolves to the granted principal"
dim "  - 'sops --decrypt infra/envs/<env>/secrets.enc.yaml' should now succeed"
log ""
log "If the principal is a role, they assume it via 'aws sts assume-role' or via"
log "an IAM Identity Center permission set that maps to it."
