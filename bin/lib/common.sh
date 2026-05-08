#!/usr/bin/env bash
#
# Shared helpers for scripts under bin/. Source this with:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Provides: REPO_ROOT, color-aware step/log/ok/warn/err/fatal, plus
# need_cmd / need_aws_auth helpers. No side effects.

# REPO_ROOT — works regardless of CWD or symlinked invocation.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_RED=$'\033[31m'
	C_BLUE=$'\033[34m'
	C_DIM=$'\033[2m'
else
	C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_DIM=""
fi

step()  { printf "\n${C_BOLD}${C_BLUE}==> %s${C_RESET}\n" "$*"; }
log()   { printf "    %s\n" "$*"; }
dim()   { printf "    ${C_DIM}%s${C_RESET}\n" "$*"; }
ok()    { printf "    ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()  { printf "    ${C_YELLOW}!${C_RESET} %s\n" "$*" >&2; }
err()   { printf "    ${C_RED}✗${C_RESET} %s\n" "$*" >&2; }
fatal() { err "$*"; exit 1; }

need_cmd() {
	command -v "$1" >/dev/null || fatal "$1 not on PATH — install it first (CLAUDE.md § Specific tool decisions)"
}

need_aws_auth() {
	aws sts get-caller-identity >/dev/null 2>&1 || \
		fatal "AWS auth failed — run 'aws sso login --profile \"\${AWS_PROFILE}\"' first"
}

confirm() {
	# confirm "Apply changes?" — returns 0 on yes, 1 on no. Defaults to no.
	local prompt="$1"
	read -rp "$prompt [y/N] " yn
	[[ "$yn" =~ ^[Yy]$ ]]
}
