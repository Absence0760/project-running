#!/usr/bin/env bash
#
# aws-preflight.sh — pre-deploy sanity check.
#
# Run this BEFORE any `terraform apply` or before invoking
# `bin/deploy-preview.sh`. It catches the failures that hurt most:
# missing tools, expired SSO session, wrong region, wrong AWS account,
# uncommitted infra changes, sops auth gaps, state-bucket missing.
#
# Read-only — never mutates anything. Exits 0 if everything is ready;
# non-zero with a list of fixes if not.
#
# Usage:
#   bin/aws-preflight.sh

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

EXPECTED_REGION="us-east-1"
STATE_BUCKET="runonward-tfstate"
FAILS=0

bump_fail() { FAILS=$((FAILS + 1)); }

step "Tooling"
for cmd in terraform aws sops jq git gh; do
	if command -v "$cmd" >/dev/null; then
		ok "$cmd ($(command -v "$cmd"))"
	else
		err "$cmd missing"
		bump_fail
	fi
done

# Terraform must be ≥ 1.10 for S3-native locking (we don't use DynamoDB).
if command -v terraform >/dev/null; then
	# Capture, don't pipe: `terraform version | head -1` SIGPIPEs terraform
	# when it prints its platform/out-of-date lines after head exits, and
	# pipefail+errexit turns that into a flaky 141 abort.
	tf_version_out="$(terraform version)"
	tf_version_line="${tf_version_out%%$'\n'*}"
	tf_version="${tf_version_line##* v}"
	tf_major="${tf_version%%.*}"
	tf_rest="${tf_version#*.}"
	tf_minor="${tf_rest%%.*}"
	if (( tf_major > 1 )) || ( (( tf_major == 1 )) && (( tf_minor >= 10 )) ); then
		ok "terraform $tf_version (≥ 1.10 — S3 native locking supported)"
	else
		err "terraform $tf_version is too old — need ≥ 1.10 (S3-native state locking)"
		bump_fail
	fi
fi

step "AWS auth"
if aws sts get-caller-identity >/dev/null 2>&1; then
	arn="$(aws sts get-caller-identity --query Arn --output text)"
	acct="$(aws sts get-caller-identity --query Account --output text)"
	ok "Authenticated as $arn"
	ok "Account: $acct"
	# Wrong-account guard. The workstation carries several SSO profiles
	# (mgmt / disag / running); applying prod terraform against the wrong
	# account is a real footgun. Pin the expected id via EXPECTED_AWS_ACCOUNT,
	# or drop it in the PRIVATE estate repo at
	# ../infra-secrets/running/aws-account, so nothing account-identifying
	# lands in this PUBLIC repo. Set + mismatch → hard fail; unset → warn
	# (the account is printed above either way, so the operator still eyeballs it).
	expected_acct="${EXPECTED_AWS_ACCOUNT:-}"
	if [[ -z "$expected_acct" ]]; then
		acct_file="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}/running/aws-account"
		[[ -f "$acct_file" ]] && expected_acct="$(tr -dc '0-9' <"$acct_file")"
	fi
	if [[ -n "$expected_acct" ]]; then
		if [[ "$acct" == "$expected_acct" ]]; then
			ok "Account matches the expected pin"
		else
			err "WRONG ACCOUNT: authenticated to $acct but expected $expected_acct — check \$AWS_PROFILE"
			bump_fail
		fi
	else
		warn "No account pin set — confirm $acct is the project-running account before applying"
		dim "Pin it: export EXPECTED_AWS_ACCOUNT=<id>  (or: echo <id> > ../infra-secrets/running/aws-account)"
	fi
else
	err "AWS auth failed — run 'aws sso login --profile \${AWS_PROFILE:-running}'"
	bump_fail
fi

# Region check — everything has to live in us-east-1 for the
# CloudFront ACM cert to work without cross-region complexity.
current_region="$(aws configure get region 2>/dev/null || echo "")"
if [[ "$current_region" == "$EXPECTED_REGION" ]]; then
	ok "Default region: $current_region"
elif [[ -z "$current_region" ]]; then
	warn "Default region unset — set it to $EXPECTED_REGION (aws configure set region $EXPECTED_REGION)"
	bump_fail
else
	warn "Default region is $current_region, expected $EXPECTED_REGION"
	dim "Each terraform stack pins its own region, so apply may still work — but a stray aws CLI call could hit the wrong region."
fi

step "State bucket (Phase 2a output)"
if aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
	ok "$STATE_BUCKET exists"
	# Check versioning + encryption — both are mandatory for tfstate.
	versioning="$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text 2>/dev/null || echo None)"
	if [[ "$versioning" == "Enabled" ]]; then
		ok "Versioning enabled"
	else
		err "Versioning is $versioning — should be Enabled"
		bump_fail
	fi
else
	warn "$STATE_BUCKET does not exist or is not accessible"
	dim "Run Phase 2a first: cd infra/bootstrap && terraform apply"
fi

step "infra/ working tree"
cd "$REPO_ROOT"
infra_dirty="$(git status --porcelain infra/ | wc -l)"
if (( infra_dirty == 0 )); then
	ok "Clean (no uncommitted changes under infra/)"
else
	warn "$infra_dirty file(s) modified under infra/ — apply will use working-tree state"
	git status --porcelain infra/ | sed 's/^/      /'
fi

step "estate secrets (.sops.yaml)"
# Prod secrets live in the PRIVATE estate repo ../infra-secrets, not here.
infra_secrets_dir="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
sops_config="$infra_secrets_dir/.sops.yaml"
if [[ ! -f "$sops_config" ]]; then
	warn "estate secrets repo not found at $infra_secrets_dir"
	dim "Clone Absence0760/infra-secrets as a sibling, or set INFRA_SECRETS_DIR."
elif grep -qE 'KMS_RUNNING_(PROD|PREVIEW)_ARN_PLACEHOLDER' "$sops_config" 2>/dev/null; then
	warn "estate .sops.yaml has unresolved running/* placeholder ARNs:"
	grep -nE 'KMS_RUNNING_(PROD|PREVIEW)_ARN_PLACEHOLDER' "$sops_config" | sed 's/^/      /'
	dim "Run bin/sops-init.sh after applying envs/<env>/."
else
	ok "estate .sops.yaml has the running/* KMS ARNs resolved"
fi

step "Verdict"
if (( FAILS > 0 )); then
	err "$FAILS hard failure(s) — fix above before applying"
	exit 1
fi
ok "Ready to apply"
