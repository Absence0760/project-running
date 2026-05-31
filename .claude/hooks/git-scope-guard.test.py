#!/usr/bin/env python3
"""Tests for git-scope-guard.py.

Runs the hook as a subprocess with crafted PreToolUse payloads and asserts
the deny/allow decision. Run: `python3 .claude/hooks/git-scope-guard.test.py`.
Not wired into CI — the hook itself is the live guard; this pins its logic so
an edit can't silently reopen a hole (notably the bare-`git commit` sweep that
let one session's commit capture another's staged changes).
"""

import json
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("git-scope-guard.py"))


def decision(command):
    """Return 'deny' if the hook blocks the command, else 'allow'."""
    out = subprocess.run(
        [sys.executable, HOOK],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True, text=True,
    ).stdout.strip()
    if not out:
        return "allow"
    try:
        return json.loads(out)["hookSpecificOutput"]["permissionDecision"]
    except (ValueError, KeyError):
        return "allow"


# (command, expected) — the core of the suite is the bare-commit gap.
CASES = [
    # The regression that motivated this guard: bare commit sweeps the index.
    ('git commit -m "msg"', "deny"),
    ("git commit", "deny"),
    ('git commit -m "msg" --no-verify', "deny"),
    # Scoped commits are safe and must pass.
    ('git commit -m "msg" -- foo.ts bar.ts', "allow"),
    ('git commit foo.ts -m "msg"', "allow"),
    ('git commit -m "msg" -- apps/web/src/lib/types.ts', "allow"),
    # Exemptions that don't race-snapshot the index.
    ("git commit --amend --no-edit", "allow"),
    ('git commit --allow-empty -m "ci: trigger"', "allow"),
    # Pre-existing rules still hold.
    ('git commit -am "msg"', "deny"),
    ('git commit -a -m "msg"', "deny"),
    ("git add -u", "deny"),
    ("git add .", "deny"),
    ("git add -A", "deny"),
    ("git add foo.ts bar.ts", "allow"),
    ("git reset --hard", "deny"),
    ("git checkout -- .", "deny"),
    ("git restore .", "deny"),
    ("git restore -- foo.ts", "allow"),
    ("git stash", "deny"),
    ("git stash push -- foo.ts", "allow"),
    ("git rm -r --cached .", "deny"),
    ("git rm .", "deny"),
    ("git rm reviews/old.md", "allow"),
    ("git rm -r reviews/data-sync-audit", "allow"),
    ("git rm --cached reviews/old.md", "allow"),
    ("git clean -fd", "deny"),
    # Read-only / unrelated — never blocked.
    ("git status", "allow"),
    ("git log --oneline -5", "allow"),
    ("git diff --cached", "allow"),
    # Compound commands: a deny anywhere in the chain blocks.
    ('git add foo.ts && git commit -m "msg"', "deny"),
    ('git add foo.ts && git commit -m "msg" -- foo.ts', "allow"),
]

failures = []
for command, expected in CASES:
    got = decision(command)
    status = "ok" if got == expected else "FAIL"
    if got != expected:
        failures.append((command, expected, got))
    print(f"  [{status}] expect {expected:5} got {got:5}  {command}")

if failures:
    print(f"\n{len(failures)} FAILED:")
    for command, expected, got in failures:
        print(f"  {command!r}: expected {expected}, got {got}")
    sys.exit(1)
print(f"\nAll {len(CASES)} cases passed.")
