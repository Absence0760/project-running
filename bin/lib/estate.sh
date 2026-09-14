#!/usr/bin/env bash
#
# The PRIVATE estate secrets repo (Absence0760/infra-secrets): where this
# project's slot is, and which sops creation rule governs a file in it. Source
# it after common.sh, which provides REPO_ROOT:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/estate.sh"
#
# The slot is named once, here. Every script that touched the estate used to
# name it for itself, so when the slot moved from running/ to threkir/ their
# comments moved and their values did not, and each went on resolving a
# directory that no longer existed. scripts/check_estate_slot.mjs fails CI when
# ESTATE_SLUG disagrees with the Terraform `secrets_file` defaults, or when any
# other file under bin/ resolves an estate path on its own.
#
# Override INFRA_SECRETS_DIR if the clone is not a sibling of this repo. No side
# effects beyond the variables below.

ESTATE_SLUG="threkir"
INFRA_SECRETS_DIR="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}"
# Resolved when the clone exists, so the paths these scripts print and hand to
# sops are one spelling of it however INFRA_SECRETS_DIR was written.
if [[ -d "$INFRA_SECRETS_DIR" ]]; then
	INFRA_SECRETS_DIR="$(cd "$INFRA_SECRETS_DIR" && pwd)"
fi
ESTATE_SLOT_DIR="$INFRA_SECRETS_DIR/$ESTATE_SLUG"
SOPS_CONFIG="$INFRA_SECRETS_DIR/.sops.yaml"

# estate_secrets_rel <env>   → threkir/<env>.sops.yaml, relative to the estate root
# estate_secrets_file <env>  → the same file as a path to open
estate_secrets_rel() { printf '%s/%s.sops.yaml\n' "$ESTATE_SLUG" "$1"; }
estate_secrets_file() { printf '%s/%s\n' "$INFRA_SECRETS_DIR" "$(estate_secrets_rel "$1")"; }

is_kms_arn() { [[ "$1" =~ ^arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+$ ]]; }

# Reads the subset of YAML the estate config is written in: a block sequence
# under a top-level `creation_rules:`, with plain, single- or double-quoted
# path_regex and kms scalars. Keys nested below a rule's own level (inside a
# key_groups entry, say) are not the rule's and are skipped.
#
# mode=list prints one line per rule — index, whether it has a path_regex, the
# regex, the kms value — separated by \037, so an empty field survives `read`
# (a whitespace IFS would collapse it). mode=set echoes the file with rule
# `target`'s kms value replaced by `value`, and exits 3 if that rule has no kms
# key to replace.
_ESTATE_RULES_AWK='
function unquote(v,    c, out, i, ch) {
	sub(/^[ \t]+/, "", v)
	c = substr(v, 1, 1)
	if (c == Q || c == "\"") {
		out = ""
		for (i = 2; i <= length(v); i++) {
			ch = substr(v, i, 1)
			if (c == Q && ch == Q) {
				if (substr(v, i + 1, 1) == Q) { out = out Q; i++; continue }
				break
			}
			if (c == "\"" && ch == "\\") { i++; out = out substr(v, i, 1); continue }
			if (c == "\"" && ch == "\"") break
			out = out ch
		}
		return out
	}
	sub(/[ \t]+#.*$/, "", v)
	sub(/[ \t]+$/, "", v)
	return v
}
function flush() {
	if (mode == "list" && idx >= 0) printf "%d\037%d\037%s\037%s\n", idx, has_re, re, kms
}
BEGIN { Q = "\047"; state = 0; idx = -1; item_ind = -1; key_ind = -1; replaced = 0 }
{
	line = $0
	rest = line
	sub(/^[ \t]+/, "", rest)
	blank = (rest == "" || substr(rest, 1, 1) == "#")
	if (state == 1 && !blank && line ~ /^[^ \t-]/) { flush(); state = 2 }
	if (state == 0 && line ~ /^creation_rules:[ \t]*(#.*)?$/) {
		state = 1
	} else if (state == 1 && !blank) {
		match(line, /^[ \t]*/)
		ind = RLENGTH
		body = substr(line, ind + 1)
		if (body ~ /^-([ \t]|$)/) {
			if (item_ind < 0) item_ind = ind
			if (ind == item_ind) {
				flush()
				idx++; has_re = 0; re = ""; kms = ""
				match(body, /^-[ \t]*/)
				body = substr(body, RLENGTH + 1)
				ind += RLENGTH
				key_ind = (body == "") ? -1 : ind
			}
		}
		if (idx >= 0 && body != "") {
			if (key_ind < 0) key_ind = ind
			if (ind == key_ind) {
				if (body ~ /^path_regex:/) {
					has_re = 1; re = unquote(substr(body, 12))
				} else if (body ~ /^kms:/) {
					kms = unquote(substr(body, 5))
					if (mode == "set" && idx == target) {
						line = substr(line, 1, ind) "kms: " Q value Q
						replaced = 1
					}
				}
			}
		}
	}
	if (mode == "set") print line
}
END {
	if (state == 1) flush()
	if (mode == "set" && !replaced) exit 3
}
'

# Prints "<index>\037<kms>" for the rule sops applies to an estate-relative
# path. sops takes the FIRST rule whose path_regex matches, and a rule without
# one matches everything, so this does the same rather than finding the rule by
# its regex text or by its placeholder's name: both are spellings, and both
# moved when the slot was renamed. bash's =~ is POSIX ERE where sops uses RE2;
# the two agree on the anchors, dots, escapes and stars these rules use.
_estate_rule_match() {
	local rel="$1" idx has_re re kms
	[[ -f "$SOPS_CONFIG" ]] || return 1
	while IFS=$'\037' read -r idx has_re re kms; do
		if [[ "$has_re" == 0 ]] || [[ "$rel" =~ $re ]]; then
			printf '%s\037%s\n' "$idx" "$kms"
			return 0
		fi
	done < <(awk -v mode=list "$_ESTATE_RULES_AWK" "$SOPS_CONFIG")
	return 1
}

# estate_rule_kms <estate-relative path>
# Prints the kms value of the rule that governs the path — an ARN once
# sops-init.sh has wired it, a placeholder before — and fails if none does.
estate_rule_kms() {
	local match
	match="$(_estate_rule_match "$1")" || return 1
	printf '%s\n' "${match#*$'\037'}"
}

# estate_set_rule_kms <estate-relative path> <arn>
# Rewrites that rule's kms value in place, keeping the file's mode. Fails with
# the file untouched when no rule governs the path or the rule has no kms key.
estate_set_rule_kms() {
	local match tmp
	match="$(_estate_rule_match "$1")" || return 1
	tmp="$(mktemp)"
	if ! awk -v mode=set -v target="${match%%$'\037'*}" -v value="$2" "$_ESTATE_RULES_AWK" "$SOPS_CONFIG" >"$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	cat "$tmp" >"$SOPS_CONFIG"
	rm -f "$tmp"
}
