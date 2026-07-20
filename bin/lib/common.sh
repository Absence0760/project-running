#!/usr/bin/env bash
#
# Shared helpers for scripts under bin/. Source this with:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Provides: REPO_ROOT, color-aware step/log/ok/warn/err/fatal, plus
# need_cmd / need_aws_auth helpers. No side effects beyond the bash
# version check below.

# Bash 4+ required: cancel-stale-runs uses associative arrays
# (`declare -A`), and several scripts rely on `${var,,}` lowercasing.
# macOS ships bash 3.2 by default — fail loudly so the user installs
# a newer bash via brew rather than seeing a cryptic "syntax error".
if (( BASH_VERSINFO[0] < 4 )); then
	printf 'bin/ scripts require bash 4+ (found %s). On macOS: brew install bash, then call scripts with /opt/homebrew/bin/bash bin/<script>.sh.\n' "$BASH_VERSION" >&2
	exit 1
fi

# REPO_ROOT — works regardless of CWD or symlinked invocation.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# README promises "$AWS_PROFILE, defaulting to running" but only
# aws-login.sh implemented the default — every bare `aws` call in the
# other scripts silently used the default profile in shells without
# the export (e.g. non-interactive ones).
export AWS_PROFILE="${AWS_PROFILE:-running}"

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

watch_sim_latest_link() {
	# Path of the "most recent watch sim" pointer symlink, written by
	# bin/watch-sim.sh and followed by bin/watch-monitor.sh.
	#
	# Scoped to this checkout, not global. It used to be one shared
	# /tmp/watch-sim.latest, so two concurrent sim sessions (two worktrees,
	# two people, two agents) overwrote each other's pointer: watch-monitor.sh
	# would silently attach to the *other* session's Renode, where a `quit`
	# killed a run that wasn't yours — and whichever sim exited first deleted
	# the pointer out from under the one still running.
	#
	# Deriving the name from REPO_ROOT keeps each checkout on its own pointer
	# while staying stable and argument-free for the normal single-session
	# case. The checksum disambiguates two checkouts with the same basename;
	# the basename is there so `ls /tmp` stays readable. WATCH_SIM_LATEST
	# overrides the whole thing.
	if [[ -n "${WATCH_SIM_LATEST:-}" ]]; then
		printf '%s\n' "$WATCH_SIM_LATEST"
		return
	fi
	local tag
	tag="$(printf '%s' "$REPO_ROOT" | cksum | cut -d' ' -f1)"
	printf '%s/watch-sim.latest-%s-%s\n' \
		"${TMPDIR:-/tmp}" "$(basename "$REPO_ROOT")" "$tag"
}
