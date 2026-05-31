#!/usr/bin/env python3
"""PreToolUse Bash guard for concurrent Claude sessions.

Blocks git commands that would sweep up working-tree changes the current
session did not make — so two (or more) Claude instances running in the same
checkout can only ever commit / discard the explicit paths they name, never
each other's in-flight edits.

It reads the PreToolUse hook payload on stdin, tokenises the command in a
quote-aware way (shlex), splits it into shell segments, and inspects each git
invocation. A blocked command is denied with a reason that points at the
path-scoped alternative; everything else is allowed through untouched.

Blocked:
  git add -A / --all / -u / --update / .          (stages the whole tree)
  git commit -a / -am / --all                      (auto-stages tracked edits)
  git stash [push|save] without `-- <path>`        (stashes the whole tree)
  git stash clear                                  (drops every stash entry)
  git reset --hard                                 (discards all working edits)
  git checkout/restore . (or :/, *) — no pathspec  (discards across the tree)
  git clean -f                                     (deletes untracked files)

Allowed: git add <path>, git commit -m, git commit -- <path>,
git restore -- <path>, git stash push -- <path>, and all read-only git.
"""

import json
import re
import shlex
import sys

PATHSPEC_ALL = {".", "*", "./", ":/", ":/.", ":/*"}


def _deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def _segments(command):
    """Split a shell command into segments on operators, respecting quotes."""
    # Treat newlines as statement separators so multi-line commands are split.
    normalised = command.replace("\n", " ; ")
    lex = shlex.shlex(normalised, posix=True, punctuation_chars=";&|<>()")
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError:
        # Unbalanced quotes etc. — don't guess, let the command through.
        return []
    segments, current = [], []
    for tok in tokens:
        if tok and all(c in ";&|<>()" for c in tok):
            if current:
                segments.append(current)
                current = []
        else:
            current.append(tok)
    if current:
        segments.append(current)
    return segments


def _git_subcommand(tokens):
    """Return (subcommand, args) for a git invocation, or None."""
    i = 0
    while i < len(tokens) and not (tokens[i] == "git" or tokens[i].endswith("/git")):
        i += 1
    if i >= len(tokens):
        return None
    i += 1
    takes_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                   "--exec-path", "--super-prefix"}
    while i < len(tokens):
        t = tokens[i]
        if t in takes_value:
            i += 2
        elif t.startswith("-"):
            i += 1
        else:
            break
    if i >= len(tokens):
        return None
    return tokens[i], tokens[i + 1:]


def _check_add(args):
    after_dd = False
    for a in args:
        if a == "--":
            after_dd = True
            continue
        if not after_dd and a.startswith("-"):
            cluster = a[1:]
            if a in ("-A", "--all", "-u", "--update", "--no-ignore-removal") \
                    or (not a.startswith("--") and ("A" in cluster or "u" in cluster)):
                return ("`git add %s` stages every change in the working tree, "
                        "including files another Claude session may be editing. "
                        "Stage only the paths you changed: `git add path/to/file ...`."
                        % a)
            continue
        if a in PATHSPEC_ALL:
            return ("`git add %s` stages everything under the repo root, which can "
                    "include another session's changes. Name explicit paths instead: "
                    "`git add path/to/file ...`." % a)
    return None


def _check_commit(args):
    skip_next = False
    saw_double_dash = False
    has_pathspec = False
    exempt = False
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a == "--":
            saw_double_dash = True
            continue
        if saw_double_dash:
            # Everything after `--` is a pathspec — the commit is scoped.
            has_pathspec = True
            continue
        if a == "--all":
            return ("`git commit --all` auto-stages every tracked modification, "
                    "including another session's. Stage your own paths explicitly "
                    "(`git add <path>`) and commit without --all.")
        if a.startswith("--"):
            # These don't snapshot the working index the racy way, so a missing
            # pathspec is fine for them (amend/merge-continuation/empty commits).
            if a in ("--amend", "--no-edit", "--allow-empty",
                     "--allow-empty-message"):
                exempt = True
            if a.startswith("--pathspec-from-file"):
                has_pathspec = True
            if a in ("--message", "--file", "--reuse-message", "--reedit-message",
                     "--fixup", "--squash", "--author", "--date", "--template",
                     "--pathspec-from-file"):
                skip_next = True
            continue
        if a.startswith("-") and len(a) > 1:
            cluster = a[1:]
            if "a" in cluster:
                return ("`git commit -%s` includes -a, which auto-stages every "
                        "tracked modification (including another session's). Drop -a, "
                        "stage your specific paths with `git add <path>`, then commit."
                        % cluster)
            if cluster[-1] in ("m", "F", "C", "c"):
                skip_next = True
            continue
        # A bare positional token is a pathspec — the commit is scoped.
        has_pathspec = True
    if not has_pathspec and not exempt:
        return ("`git commit` with no pathspec commits the ENTIRE staged index — in a "
                "shared checkout that sweeps up whatever another Claude session has "
                "staged (this has happened). Commit only your own paths: "
                "`git commit -m \"…\" -- path/to/file ...` (a path-scoped commit "
                "ignores anything else staged). Use --amend / --allow-empty if you "
                "genuinely have no paths.")
    return None


def _check_stash(args):
    if not args:
        return ("`git stash` stashes the entire working tree, including another "
                "session's changes. Use `git stash push -- <path>` to limit it, or "
                "avoid stashing in a shared checkout.")
    op = args[0]
    if op in ("push", "save"):
        if "--" in args:
            return None
        return ("`git stash %s` without `-- <path>` stashes the whole working tree, "
                "including another session's changes. Pass `-- <path>` to limit it."
                % op)
    if op == "clear":
        return ("`git stash clear` deletes every stash entry, including another "
                "session's. Drop only your own entry by index if you must.")
    return None


def _check_reset(args):
    if "--hard" in args:
        return ("`git reset --hard` discards ALL uncommitted changes in the working "
                "tree, including another session's. To unstage your own files use "
                "`git restore --staged <path>`; to discard your own edits use "
                "`git restore <path>`.")
    return None


def _check_discard(name, args):
    after_dd = False
    paths = []
    for a in args:
        if a == "--":
            after_dd = True
            continue
        if not after_dd and a.startswith("-"):
            continue
        paths.append(a)
    for p in paths:
        if p in PATHSPEC_ALL:
            return ("`git %s %s` discards working-tree changes across the whole repo, "
                    "including another session's. Restore only your paths: "
                    "`git %s -- path/to/file`." % (name, p, name))
    return None


def _check_clean(args):
    forced = "--force" in args or any(
        a.startswith("-") and not a.startswith("--") and "f" in a[1:] for a in args
    )
    if forced:
        return ("`git clean` deletes untracked files, which may include new files "
                "another session just created. Delete only the specific files you "
                "created instead of cleaning the whole tree.")
    return None


CHECKS = {
    "add": _check_add,
    "commit": _check_commit,
    "stash": _check_stash,
    "reset": _check_reset,
    "checkout": lambda a: _check_discard("checkout", a),
    "restore": lambda a: _check_discard("restore", a),
    "clean": _check_clean,
}


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, json.JSONDecodeError):
        sys.exit(0)
    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    command = (payload.get("tool_input") or {}).get("command") or ""
    if "git" not in command:
        sys.exit(0)
    for tokens in _segments(command):
        parsed = _git_subcommand(tokens)
        if not parsed:
            continue
        sub, args = parsed
        check = CHECKS.get(sub)
        if check:
            reason = check(args)
            if reason:
                _deny(reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
