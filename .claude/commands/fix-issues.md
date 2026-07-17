---
description: Fix N open GitHub issues in parallel — one worktree-isolated agent per issue, each fixing at the root web-first with twin parity + i18n + tests + docs, then opening a PR. Defaults to 5 issues / 5 agents.
argument-hint: "[count | issue numbers | label filter] [single-pr] — e.g. \"5\", \"#303 #252 #250\", \"label:bug 5\", \"single-pr\". Omit to fix 5 open issues, one PR each."
---

Fix open GitHub issues in this repo using **parallel agents — one per issue** — then open a PR for the work. Scope: `$ARGUMENTS` (if empty, fix **5** open issues, each in its own PR).

This is a **fan-out fix** loop: **select → confirm → fan out (one worktree per issue) → each agent fixes + tests + PRs → collect → report.**

## Why worktrees are mandatory here

Several Claude sessions share this one checkout and a single git index ([CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)). Five agents editing files in the *same* tree would clobber each other's work and each other's commits. So **every fixer agent MUST run with `isolation: "worktree"`** — its own tree, its own index, its own branch off `origin/main`. This is the only parallel-safe design in this repo. Do not fan out file-editing agents into the shared checkout.

## When to use this command

**Right fit:**
- "Burn down the issue backlog" — several independent, well-scoped, code-fixable issues.
- Issues that are concrete bugs or small enhancements with an obvious root-cause fix.

**Wrong fit — don't run (or drop the issue from the batch):**
- Issues needing a **product decision** first, or tagged gated-on-owner/CISO/counsel (write-behind-a-flag rules still apply, but don't auto-ship a compliance-gated feature from a batch job).
- Issues that are **discussions / questions / duplicates** with no code change.
- One large issue that is really a feature epic — use `/improve-round` or `/safe-edit` on it directly.

## The loop

### 1. Select the issues (orchestrator — not parallel)

Parse `$ARGUMENTS`:
- A bare number (`5`) → how many issues to fix (default **5**).
- Explicit issue numbers (`#303 #252 …`) → fix exactly those.
- A `label:` filter (`label:bug`) → restrict the candidate pool.
- `single-pr` anywhere → consolidate all fixes into **one** PR instead of one-per-issue (see step 5).

List candidates and pick the batch:

```
gh issue list --state open --limit 40 --json number,title,labels,body
```

Choose issues that pass the **actionable bar**: a concrete, bounded, code-level fix with a clear root cause; not blocked on a product call or a compliance sign-off; not a duplicate/discussion. Prefer `bug` over `enhancement` when choosing freely. Read each candidate's body — skip anything whose "fix" is really "decide what we want."

If fewer than the requested count are actionable, take what qualifies and say so — don't pad the batch with issues that need a decision.

### 2. Confirm before spending (checkpoint)

Opening PRs is an outward-facing action. Before fanning out, print the selected issue numbers + titles + the one-line fix intent for each, and the PR strategy (one-per-issue vs `single-pr`), and get a go-ahead. If the user invoked the command with explicit issue numbers, treat that as the go-ahead and proceed.

### 3. Fan out — one worktree-isolated agent per issue (in a single message)

Spawn all fixer agents in one message so they run concurrently. Each is a `general-purpose` agent with `isolation: "worktree"`, scoped to **exactly one issue**. Give each agent this contract:

> You are fixing GitHub issue **#N** in an isolated git worktree. Work only on this issue.
>
> 1. **Reproduce / locate.** Read the issue body. Find the root cause in the code — cite `file:line`. If you cannot reproduce or the fix needs a product decision, stop and report that instead of guessing.
> 2. **Fix at the root, web-first.** Web is the canonical surface ([decisions §24](../../docs/architecture/decisions.md)). No band-aids, no widened timeouts/retries/skips to hide a bug ([CLAUDE.md § Always recommend the long-term solution](../../CLAUDE.md)).
> 3. **Honor the invariants:** twin parity (mirror `apps/mobile_android/lib|test` edits into `apps/mobile_ios`, and keep any TS↔Dart parity helper in lockstep — run `shared-library-syncer`); paywall gates; fail-closed defaults; layered resilience on the recording stack; no emojis; zero-comment default.
> 4. **i18n:** any new user-facing string → all six web locales + all mobile ARBs.
> 5. **Tests in the SAME commit as the fix** — a pinning unit test (or Playwright e2e for a web UI path, pgtap/Deno for backend) that fails before and passes after. A fix with no test is not done.
> 6. **Docs:** update whatever the change touches per [CLAUDE.md § Docs hygiene](../../CLAUDE.md) (roadmap/parity/features/per-app CLAUDE.md), and regenerate both type files if you touched schema.
> 7. **Commit path-scoped, per piece** (`git commit -m "…" -- <paths>`); conventional-commit messages; **no AI attribution** of any kind.
> 8. Run the relevant checks (`npm test`/`dart test`/`flutter test`, `npm run gen:types:check` if schema moved) and report pass/fail honestly — do not claim green you didn't see.
> 9. **Report back:** branch name, the commits, files touched, test result, and a proposed PR title (conventional-commit format `type(scope): subject`, lowercase, ≤70 chars, no trailing period — the PR title lint gate will reject otherwise) + body ending with `Fixes #N`.

Keep each agent's scope to its one issue so it reads deeply and doesn't wander.

### 4. Verify each agent's work before it becomes a PR

Don't trust a "done" — for each returned fix, sanity-check: the cited root cause is real, the test genuinely fails-before/passes-after, the twin + i18n + docs obligations were met, and no unrelated files were swept in. Bounce anything that swallowed a failure or papered over the bug back to the agent (via `SendMessage` to keep its worktree context) rather than shipping it.

### 5. Open the PR(s)

Push is a distinct action — the command opening PRs is authorized by the user invoking it, but never `--force` and never touch `main` directly.

- **Default — one PR per issue** (recommended; matches branch protection + the PR-title lint's one-`type(scope)` rule, and keeps unrelated changes independently reviewable/revertable):
  ```
  git push -u origin <agent-branch>
  gh pr create --title "<conventional title>" --body "$(printf '…\n\nFixes #N')" --base main
  ```
- **`single-pr` mode** — create one integration branch off `origin/main`, merge each worktree branch into it, resolve any conflicts, push, and open **one** PR whose body lists `Fixes #N1`, `Fixes #N2`, … for every issue in the batch. Pick the dominant `type` and a representative `scope` for the title. Use this only when the user asked for it — a five-issue PR spanning unrelated areas is harder to review and to revert.

Each PR must pass the single required **CI gate** check; report if any open red.

### 6. Report

One compact table: issue # → PR URL → test result → CI status. Note any issue that was dropped (not actionable) and why. Clean up finished worktrees (`git worktree remove`) unless a fix is still being iterated.

## Guardrails

- **Fixes only what the issues describe.** No scope creep, no drive-by refactors bundled in.
- **Never merge the PRs** — opening them is the deliverable; merge is the user's call.
- **A dropped issue is a fine outcome.** Reporting "3 of 5 were actionable; the other 2 need a product decision" is better than shipping two guesses.
- If a fix touches a security-sensitive / schema / state-machine surface, the agent should run it through the `/safe-edit` rigor (coder↔`code-reviewer` loop) rather than a single pass.
