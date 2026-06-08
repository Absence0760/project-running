---
description: Ship one meaningful improvement to an area of the app — web-first, in path-scoped per-piece commits with tests + twin parity + i18n + docs — then run an independent code-reviewer audit and fix every finding until clean. The "do another round" loop.
argument-hint: [area or feature — optional; omit to let the command pick a high-value target]
---

Pick (or take) one area of the app, ship a genuinely useful improvement to it, then audit your own work with the `code-reviewer` agent and fix what it finds. Target: `$ARGUMENTS` (if empty, survey for a high-value target and propose it before building).

This is the repeatable "do another round of this" loop: **improve → commit per piece → audit → fix → re-audit → report.**

## When to use this command

**Right fit:**
- "Do another round" / "improve some area of the app" with latitude to choose.
- A specific area the user named that has a real gap, a missing interconnection between features, or a shipped-but-half-finished surface.
- Anywhere a small, self-contained, verifiable improvement plus a regression guard raises quality.

**Wrong fit — push back instead of running:**
- A large, uncertain feature that needs a product decision first (use `AskUserQuestion` / `EnterPlanMode`, don't free-run).
- A pure bug report with a known fix (just fix it; this loop is for *improvements* you scope yourself).
- Trivial edits (typos, dep bumps) — no round needed.

## Principles (the bar these rounds are held to)

- **Web is canonical** ([decisions §24](../../docs/architecture/decisions.md)). Build the improvement on web first. Mobile/watch mirror later.
- **Real gap, not churn.** Pick something with user value: a missing signal (e.g. "warn before a shoe is worn out"), a feature that should be interconnected but isn't (e.g. "today's run should raise the nutrition goal"), or a shipped surface that's inconsistent with the rest of the app. Confirm the gap is real by reading the code before building — don't assume.
- **Recommend the long-term solution and do it fully** (CLAUDE.md). No band-aids; fix the root cause and extract the reusable piece when there is one.
- **Pin every fix with a test** so it can't regress — a unit test for pure logic, an e2e for a UI path, or a source-scan guard for a class of mistake.

## The loop

### 1. Choose the target (if `$ARGUMENTS` is empty or vague)

Survey for a high-value, bounded improvement. Read the relevant code to confirm the gap is real (a surface that's missing a signal, two features that should talk but don't, a pre-existing inconsistency). State the chosen target + why in one or two sentences, then build it. If the best target needs a product call, surface it with `AskUserQuestion` first.

### 2. Decompose into pieces and build, committing as you go

Per [CLAUDE.md § Commit cadence](../../CLAUDE.md), each discrete piece is its own commit, tests in the **same** commit as the code:

- **Pure logic** → extract to a testable module (`apps/web/src/lib/<area>/<name>.ts`), unit-test it. If a `.svelte.ts` would trap runes, keep the pure part in a sibling `.ts` (see `apps/web/CLAUDE.md`).
- **TS↔Dart parity helper** → if mobile already uses the same logic, write the Dart twin in lockstep and run `shared-library-syncer`; register the pair in `CLAUDE.md` + `.claude/agents/shared-library-syncer.md`. If mobile does **not** use it yet, keep it **web-only** (don't create a dead twin) and add a `docs/product/followups.md` mobile-mirror entry instead.
- **Dart edits** → run `mobile-twin-mirror` to keep `apps/mobile_ios` byte-identical, in the same commit.
- **User-facing strings** → add the key to all six locales (`apps/web/src/lib/i18n/locales/*`); `messages_parity.test.ts` enforces parity. Run it.
- **Schema** → use `/safe-migration` instead; this loop is not for migrations.
- **Docs** → update in the same turn ([CLAUDE.md § Docs hygiene](../../CLAUDE.md)): `apps/web/CLAUDE.md`, `decisions.md` (one paragraph if a non-obvious trade-off), `parity.md` if platforms shift, `followups.md` for any deferred mirror.

**Commit discipline (shared working tree — [CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)):**
- Always path-scoped: `git commit -m "…" -- path1 path2 …`. Never `git add -A`/`-u`, never a bare `git commit`.
- One piece = one commit. `git status` before each commit; confirm every path is yours.
- No AI attribution / `Co-Authored-By` / robot footer in messages (user-level rule).
- Commit only — never `git push` without an explicit ask.

### 3. Verify each piece before moving on

Run the cheapest sufficient check: `npx tsx --test <file>` for unit tests, `flutter test <file>` for Dart, `npm run check --workspace=apps/web` for types (treat only **new** errors as yours — the repo carries some pre-existing ones), the relevant Playwright spec for a UI path, `messages_parity` for i18n. Don't declare a piece done on an unrun test.

### 4. Audit the round with `code-reviewer`

When the build is committed, spawn the `code-reviewer` agent against your commit **range** (not the working tree — it's already committed):

> "Review the diff of the last N commits on `main` (`git diff HEAD~N..HEAD`). <one-line description of what the round did>. Review for real correctness bugs and project-convention violations (decisions ADRs, TS↔Dart parity lockstep, layered resilience, fail-closed defaults, i18n parity, accessibility/contrast, comment + abstraction discipline). Report concrete diff-level findings with file:line + recommended fix. Do not edit."

### 5. Fix every finding — but verify the finding first

For each Critical / Improvement:
- **Confirm it's real before acting.** If the finding makes a *numeric* claim (a contrast ratio, a threshold, an off-by-one), **compute it yourself** — a past round "fixed" a dark-mode contrast bug by introducing a light-mode one because the suggested value wasn't checked. Don't trade one bug for another.
- If real, fix the **root cause**, and if the same mistake exists elsewhere (a copied pattern), fix those instances in the same turn — don't leave the broken pattern to be recopied.
- If the finding is wrong, say *why* you're not applying it; don't silently skip.
- **Watch for half-migrations.** If the round changed the meaning of a shared, cross-device setting (a `user_settings` pref), don't reword/relabel one platform while the other still computes the old way — that ships a setting that means two different things. Either complete both surfaces or keep the labels matching the per-platform behaviour and document the ordering constraint in `followups.md`.
- Pin the fix with a test/guard, then commit it path-scoped (its own `fix(...)` commit).

### 6. Re-audit if the fixes were non-trivial; cap at 2 cycles

If step 5 changed real logic, re-run `code-reviewer` on the new commits. Stop after the second cycle even if minor nits remain — report them instead of looping.

### 7. Report

Short summary: what the round improved + why it mattered, the audit findings and how each was resolved (or why dismissed), what's verified (tests/guards), and any pre-existing-but-related issue you surfaced for a future round. End with a one-line offer to run another round or pick a different area.

## Tone

- Don't narrate agent fan-out or every command. The user reads the diffs.
- Be honest about scope: name what you deliberately deferred (and where it's tracked) versus what you finished.
- 1–2 sentence end-of-turn summary per CLAUDE.md — let the commits speak.
