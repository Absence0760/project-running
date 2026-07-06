#!/usr/bin/env bash
#
# secret-set.sh — set or update a single key in an env's encrypted secrets
# file (../infra-secrets/running/<env>.sops.yaml, in the PRIVATE estate repo)
# without opening the editor.
#
# This wraps `sops --set` so you can script secret rotations or one-
# off changes without launching $EDITOR. Re-encrypt happens
# automatically as part of the set.
#
# The value is read from stdin or a file — NEVER as a positional
# argument — to keep secrets out of shell history and `ps` output.
#
# Usage:
#   echo "sk-ant-…" | bin/secret-set.sh preview ANTHROPIC_API_KEY
#   bin/secret-set.sh prod SUPABASE_SERVICE_ROLE --from-file ~/svc.txt
#   bin/secret-set.sh preview ANTHROPIC_API_KEY --prompt
#
# Modes:
#   stdin (default)   read until EOF, strip ONE trailing newline
#   --from-file PATH  read entire file, strip ONE trailing newline
#   --prompt          read with `read -s` (no echo), one line
#
# Trailing-newline note:
#   Only ONE trailing newline is stripped. `echo "x" | …` (which adds
#   exactly one) gives you `x`, the common case. For a multi-line
#   secret like a PEM private key, internal newlines are preserved
#   verbatim. If your input has multiple trailing blank lines, those
#   beyond the first are kept in the value — usually a paste mistake;
#   strip them before piping in.
#
# After running, re-apply the env so the Lambda picks up the new
# value:
#
#   cd infra/envs/<env> && terraform apply

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Secrets live in the PRIVATE estate repo ../infra-secrets/running/, NOT this
# public repo. Override INFRA_SECRETS_DIR if your clone isn't a sibling.
INFRA_SECRETS_DIR="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
PROJECT_SLUG="running"

usage() {
	cat >&2 <<EOF
Usage: bin/secret-set.sh <env> <key> [--from-file <path> | --prompt]

  env    preview | prod
  key    e.g. ANTHROPIC_API_KEY (must match [A-Z_][A-Z0-9_]*)

  Without a flag, the value is read from stdin (until EOF, trailing
  newline stripped). Use --from-file to read a path, or --prompt to
  type interactively without echo.

Examples:
  echo -n "\$VALUE" | bin/secret-set.sh preview ANTHROPIC_API_KEY
  bin/secret-set.sh prod SUPABASE_SERVICE_ROLE --from-file ~/svc.txt
  bin/secret-set.sh preview ANTHROPIC_API_KEY --prompt
EOF
	exit 2
}

if [[ $# -lt 2 ]]; then usage; fi

ENV_NAME="$1"
KEY="$2"
shift 2

case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac

# Strict KEY shape — sops's `--set ['<KEY>']` syntax can be confused
# by special characters, and Lambda env-var names must match this anyway.
if ! [[ "$KEY" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
	fatal "Invalid key: $KEY (must match [A-Z_][A-Z0-9_]*)"
fi

MODE="stdin"
FROM_FILE=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--from-file)
			MODE="file"; FROM_FILE="$2"; shift 2 ;;
		--prompt)
			MODE="prompt"; shift ;;
		*)
			fatal "Unknown flag: $1" ;;
	esac
done

need_cmd sops
need_cmd jq

SECRETS_FILE="$INFRA_SECRETS_DIR/$PROJECT_SLUG/$ENV_NAME.sops.yaml"

# Validate input source BEFORE we hit AWS — a piped-empty stdin or
# missing --from-file path should error fast with the real reason,
# not a misleading "AWS auth failed".
case "$MODE" in
	stdin)
		if [[ -t 0 ]]; then
			fatal "stdin is a TTY — pipe the value in, or use --from-file or --prompt"
		fi
		# `printf x` + strip guards the command substitution's
		# strip-ALL-trailing-newlines behaviour — the documented contract
		# is byte-exact input minus exactly ONE trailing newline (below).
		VALUE="$(cat; printf x)"
		VALUE="${VALUE%x}"
		;;
	file)
		if [[ ! -r "$FROM_FILE" ]]; then
			fatal "--from-file: cannot read $FROM_FILE"
		fi
		VALUE="$(cat "$FROM_FILE"; printf x)"
		VALUE="${VALUE%x}"
		;;
	prompt)
		read -rsp "Value for $KEY (input hidden): " VALUE
		echo >&2
		;;
esac

# Strip a single trailing newline (very common from `echo` and editor
# saves) so secrets aren't accidentally stored with a `\n` suffix.
VALUE="${VALUE%$'\n'}"

if [[ -z "$VALUE" ]]; then
	fatal "Empty value — refusing to set $KEY"
fi

# AWS / file checks last — these need network or disk and are the
# slowest, so do the cheap validation above first.
need_aws_auth

if [[ ! -f "$SECRETS_FILE" ]]; then
	fatal "$SECRETS_FILE missing — run bin/sops-init.sh $ENV_NAME first"
fi

# sops --set expects a JSON-encoded string. jq -Rn handles quotes,
# backslashes, and newlines safely — never interpolate raw $VALUE.
JSON_VALUE="$(jq -Rn --arg v "$VALUE" '$v')"
sops --config "$INFRA_SECRETS_DIR/.sops.yaml" --set "[\"$KEY\"] $JSON_VALUE" "$SECRETS_FILE"

ok "Set $KEY in $SECRETS_FILE"
log ""
log "Commit the encrypted file in the PRIVATE estate repo (never in this one):"
dim "  (cd $INFRA_SECRETS_DIR && git add $PROJECT_SLUG/$ENV_NAME.sops.yaml && git commit -m 'running: rotate $KEY')"
log "Push to the Lambda:"
dim "  cd infra/envs/$ENV_NAME && terraform apply"
