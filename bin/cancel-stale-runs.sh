#!/usr/bin/env bash
#
# cancel-stale-runs.sh — cancel any in-progress / queued GitHub
# Actions run whose head branch belongs to a closed or merged PR.
#
# Came up the day Dependabot opened 14 PRs at once and we ended up
# with stale per-PR CI runs still chewing through runner minutes long
# after the PRs were merged.
#
# Usage:
#   bin/cancel-stale-runs.sh           # dry run — show what would be cancelled
#   bin/cancel-stale-runs.sh --apply   # actually cancel them

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

APPLY=0
for arg in "$@"; do
	case "$arg" in
		--apply) APPLY=1 ;;
		*) fatal "Unknown flag: $arg" ;;
	esac
done

need_cmd gh
need_cmd jq

step "Listing in-progress + queued runs"
runs_json="$(gh run list --limit 50 \
	--json databaseId,status,workflowName,headBranch,event \
	--jq '[.[] | select(.status == "in_progress" or .status == "queued")]')"
total="$(echo "$runs_json" | jq 'length')"
log "$total live runs"

if [[ "$total" -eq 0 ]]; then
	ok "No live runs"
	exit 0
fi

# Cache PR-state lookups per branch to avoid 1-API-call-per-run.
# Map: branch → "OPEN" | "CLOSED" | "MERGED" | "" (no PR).
declare -A pr_state_for

pr_state_for_branch() {
	local branch="$1"
	if [[ -n "${pr_state_for[$branch]+x}" ]]; then
		echo "${pr_state_for[$branch]}"
		return
	fi
	# `--head` matches the branch; pick the most recent PR if multiple.
	local out
	out="$(gh pr list --state all --head "$branch" --limit 1 \
		--json number,state,mergedAt 2>/dev/null || echo "[]")"
	local state
	state="$(echo "$out" | jq -r '.[0].state // empty')"
	pr_state_for["$branch"]="$state"
	echo "$state"
}

step "Triaging"
to_cancel=()
to_keep=()

while IFS= read -r row; do
	id="$(echo "$row" | jq -r .databaseId)"
	wf="$(echo "$row" | jq -r .workflowName)"
	branch="$(echo "$row" | jq -r .headBranch)"
	event="$(echo "$row" | jq -r .event)"

	# Runs on `main` (or any direct push to a tracked branch) are
	# legitimate — never cancel. Same for tag pushes.
	if [[ "$event" != "pull_request" ]]; then
		to_keep+=("$id|$wf|$branch|kept (event=$event)")
		continue
	fi

	state="$(pr_state_for_branch "$branch")"
	case "$state" in
		MERGED|CLOSED) to_cancel+=("$id|$wf|$branch|PR is $state") ;;
		OPEN)          to_keep+=("$id|$wf|$branch|PR is OPEN") ;;
		"")            to_keep+=("$id|$wf|$branch|no PR found (orphan branch?)") ;;
	esac
done < <(echo "$runs_json" | jq -c '.[]')

step "Would keep ($((${#to_keep[@]})))"
for line in "${to_keep[@]}"; do
	IFS='|' read -r id wf branch reason <<< "$line"
	dim "  #$id  $wf  $branch  ($reason)"
done

step "Would cancel ($((${#to_cancel[@]})))"
if (( ${#to_cancel[@]} == 0 )); then
	ok "No stale runs to cancel"
	exit 0
fi
for line in "${to_cancel[@]}"; do
	IFS='|' read -r id wf branch reason <<< "$line"
	log "  #$id  $wf  $branch  ($reason)"
done

if [[ $APPLY -eq 0 ]]; then
	log ""
	dim "Re-run with --apply to actually cancel."
	exit 0
fi

step "Cancelling"
for line in "${to_cancel[@]}"; do
	IFS='|' read -r id _ _ _ <<< "$line"
	gh run cancel "$id" 2>&1 | sed 's/^/      /'
done
ok "Cancelled ${#to_cancel[@]} run(s)"
