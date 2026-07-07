# Contributing

Thanks for considering a contribution. This file describes how to work in this repo.

## Before you start

- Open an issue (or comment on an existing one) describing what you want to change. For non-trivial changes, get rough agreement on the approach before opening a PR — it's easier to redirect a sentence than a 500-line diff.
- Look at recent commits in the area you're touching for style cues.
- Stack-specific dev setup is in `docs/STACK.md`.

## Branching

Work on a feature branch off `main`:

```
git checkout -b feat/<short-slug>      # for features
git checkout -b fix/<short-slug>       # for bug fixes
git checkout -b chore/<short-slug>     # for tooling / housekeeping
git checkout -b docs/<short-slug>      # for docs only
```

Keep branches short-lived. If you're working on something that'll take more than a couple of days, rebase onto `main` regularly to avoid drift.

## Commits

Use conventional-commit-style messages:

```
feat(scope): add the thing
fix(scope): stop the crash on Y
chore(scope): bump dependency Z
docs(scope): clarify the setup steps for X
```

Scope is the area you're touching (e.g. `frontend`, `backend`, `infra`, `auth`, `audit`, etc.). Keep the subject line under 70 characters; put rationale in the body if the change isn't self-evident.

## Tests + docs are part of the change

Per the rule in `CLAUDE.md`: every PR that touches code also touches tests and docs in the same diff. If a change is genuinely untestable (config, pure styling, a one-line constant), say so in the PR description — don't skip silently.

## Running the checks locally

```
pnpm install               # bootstrap (or the stack's equivalent)
pnpm check                 # typecheck across workspaces
pnpm test                  # unit / integration tests
pre-commit run --all-files # gitleaks + the other hygiene hooks
```

Or, if Claude Code is available: `/check` runs all of the above in sequence and reports.

## Opening a PR

- Title: same conventional-commit format as commits.
- Description: fill in the `pull_request_template.md`. The "Money / data safety checklist" is there for a reason — even ticking the boxes is a useful prompt to think through each item.
- Mark as **Draft** while CI is still running; flip to ready when checks are green.
- Don't squash on merge unless you're cleaning up a noisy WIP series — preserving meaningful commits in `main` makes `git blame` more useful.

## Merge requirements

`main` is protected. To merge you need:

- **An open PR** — direct pushes to `main` are blocked, including for admins. Every change reaches `main` through a PR.
- **A green `CI gate` status check** — this single required check is an aggregator that fans in on the full CI job set (and is reported for docs-only PRs too). It, not a human, is the merge gate.

There are **no required approvals** — review is encouraged but not a merge gate. History is linear (rebase / merge-commit, not force-push), and all PR conversations must be resolved before merge.

## Reviewing a PR

- Pull the branch locally, run the test suite, exercise the change manually if it's user-visible.
- The `/code-reviewer` agent (in `.claude/agents/`) can produce a first-pass review. Review is a quality practice here, not a merge gate (see Merge requirements above) — a human read is still valuable, especially for security, schema, or recording-stack changes.

## Security findings

If you discover a vulnerability, **do not** open a public issue or PR. Email the maintainer directly — `SECURITY.md` has the contact and the response SLA.
