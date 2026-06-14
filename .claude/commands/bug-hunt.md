---
description: Run rounds of bug hunting on a surface — fan out read-only hunters, triage by confidence × impact, verify each finding, then fix the real ones at the root cause with a pinning test in the same commit. The "find and kill concrete bugs" loop.
argument-hint: [surface or area — optional; e.g. "web pure-logic helpers", "the Go worker", "Edge Functions + SQL", "run_recorder", "Wear OS". Omit to let the command pick a surface.]
---

Hunt for **concrete logic bugs** on a surface, then fix the real ones — each at its root cause, with a pinning test in the same commit. Target: `$ARGUMENTS` (if empty, pick a surface that hasn't been swept recently and say which before hunting).

This is the repeatable "do another round of bug hunting" loop: **hunt → triage → verify → fix + pin → commit per piece → report.** Run it once for one round, or repeatedly across surfaces.

## When to use this command

**Right fit:**
- "Do some rounds of bug hunting" / "find and fix bugs in X" with latitude to choose targets.
- Sweeping a self-contained surface (a set of pure-logic helpers, one Go service, the Edge Functions + SQL, the recording stack, a native watch app) for real defects.
- Hardening before a release, or after a big feature landed and you want a defect sweep.

**Wrong fit — do something else instead:**
- A *known* bug with a known fix → just fix it (this loop is for *finding* them).
- A *missing feature* or a quality/consistency improvement → use `/improve-round` (that loop scopes improvements; this one kills defects).
- A single security-sensitive / schema / state-machine change → use `/safe-edit` or `/safe-migration` directly.

## What counts as a bug (the triage bar)

A finding is only worth fixing when **both** hold:
1. The behaviour is **genuinely wrong** — not undefined-by-design, not a documented trade-off, not a style preference.
2. The **existing tests don't already cover it** (else it's not latent — it's pinned and correct).

Reject, and don't burn a commit on: missing features, "consider refactoring", speculative "could overflow if…", or anything a persona hunter frames as a UX gap rather than a defect. Rank survivors by **confidence × impact** and fix the top ones; a LOW-confidence "arguably intentional" finding either gets confirmed into HIGH or gets left with a one-line note, not papered over.

## The loop

### 1. Pick the surface (if `$ARGUMENTS` is empty or vague)

Choose one bounded surface with real bug potential and say which + why in a sentence. Good surfaces this repo rewards: the pure-logic helpers (`apps/web/src/lib/**` math/parse/date modules) and their Dart twins, the Go worker + live-hub (`apps/job_worker/`), Edge Functions + SQL triggers/RPCs (`apps/backend/supabase/`), the shared recording engine (`packages/run_recorder/`), the native watch apps (`apps/watch_wear` Kotlin, `apps/watch_ios` Swift). Don't re-sweep a surface you just cleaned.

### 2. Fan out read-only hunters (in parallel)

Spawn hunters in a single message so they run concurrently. Two flavours, both **read-only** (they report, they don't edit):

- **Code-level logic hunters** — `general-purpose` agents, each pointed at a named file list with the instruction: find CONCRETE logic bugs (off-by-one, NaN/Infinity/div-by-zero, wrong rounding, unit conversion, boundary/empty/null/negative, mutation of inputs, timezone/date arithmetic, wrong comparison/operator, accumulation drift, parsing/round-trip edge cases, concurrency/races, swallowed errors, context-cancellation, off-by-one in slicing). For each: `file:line`, a concrete failing input → wrong output → expected output, and confidence. **Tell them a bug is only real if the tests don't already cover it.** This is the workhorse — read the code yourself in parallel.
- **Persona hunters** (`runner-*`, `runner-woman`, `runner-older`, `moab240-*`, `ws100-*`, `utmb-*`, `boston-*`, `backyard-*`, `garmin-ciq-*`, …) — use when hunting from a real user's perspective surfaces edge cases code-reading misses (an ultra runner's 100-hour recording, a backyard-ultra's loop-count semantics). They lean toward UX-gap findings, so triage hard against the bar above.

Keep each hunter's scope tight (a handful of files) so it reads deeply rather than skimming.

### 3. Verify every finding before touching code

This is the step that separates a real fix from a regression:
- **Read the cited code yourself.** Confirm the wrong behaviour is reachable and the tests genuinely miss it. Hunters are confidently wrong sometimes (a suggested fix may not even work — e.g. a proposed `onConflict` target that still fails against a *partial* unique index).
- **Compute any numeric claim** (a threshold, a ratio, an off-by-one) rather than trusting it.
- **For SQL/DB findings, prove it against the running stack** (`psql` on `127.0.0.1:54322`): reproduce the wrong result, and confirm your fix produces the right one. (e.g. demonstrate `ON CONFLICT (...) → 42P10` before rewriting the upsert.)
- Check whether the same defect is **copied elsewhere** — fix all instances, don't leave the pattern to be recopied.

### 4. Escalate the intricate ones — don't rush them

If the correct fix touches a **state machine, a security/privacy boundary, a schema, or involves a product decision** (e.g. how to split a GPS-gap jump across crossed workout steps for adherence scoring), stop and route it through `/safe-edit` (coder↔reviewer loop) or `/safe-migration`, or surface the decision with `AskUserQuestion`. A hasty fix to load-bearing logic that ships wrong data is worse than a flagged finding. Say so explicitly rather than forcing it into a rapid round.

### 5. Fix the root cause + pin it, one bug per commit

Per [CLAUDE.md § Commit cadence](../../CLAUDE.md), each fix is its own commit with its test in the **same** commit:
- **Fix the root cause**, not the symptom — never inflate a timeout/retry/skip to hide it ([CLAUDE.md](../../CLAUDE.md)).
- **Pin it with a test that fails on the old code and passes on the new.** Unit (`npx tsx --test <file>` / `flutter test <file>`), pgtap or a Deno test for backend, a Go `_test.go`, a Playwright spec for a UI path. For SQL, **negative-check**: run the new pgtap test against the *old* function body and confirm it reports `not ok`, then restore the fix.
- **Pin the whole class, not just the one input — so the bug can't resurface through a near-miss.** A single happy-path assertion is not enough: add the adjacent cases that share the root cause (the other ordering, the boundary on each side, the empty/null/negative/zero input, the "largest of several" vs "first of several", the element that should be *excluded*). Aim for the smallest set of cases that would have caught the bug from any direction, and verify at least the headline case fails on the old code. The fix and its full regression block ship in the **same commit**.
- **Every bug surfaced in this loop gets pinned this way — including ones found incidentally** while verifying or fixing the headline finding. Don't fix a second bug bare because "the test was for the first one"; a fix with no test is not done. If a surfaced bug is verified-but-deferred (needs a product call / `/safe-edit` / schema change), record it in `docs/product/followups.md` rather than leaving it untested and untracked.
- **Twin parity:** any edit under `apps/mobile_android/lib/` or `test/` mirrors to `apps/mobile_ios` byte-for-byte (run `mobile-twin-mirror`); a TS↔Dart parity-pair edit runs `shared-library-syncer`. When a helper genuinely can't hit the bug on the other platform (e.g. a non-nullable Dart field where the TS type is structurally nullable), say so and skip the mirror with that reasoning — don't add a dead twin.
- **Docs:** if behaviour a doc describes changed, update it the same turn ([CLAUDE.md § Docs hygiene](../../CLAUDE.md)) — including stale `derived_state.md` / `metadata.md` contracts a fix exposes.

**Commit discipline (shared working tree — [CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)):**
- Always path-scoped: `git commit -m "…" -- path1 path2 …`. `git add <new-file>` is allowed for new files, but never `git add -A`/`-u`, never a bare `git commit`.
- One bug = one commit. `git status` before each; confirm every path is yours.
- No AI attribution / `Co-Authored-By` / robot footer (user-level rule). Commit only — never `git push` without an explicit ask.

### 6. Report

Short summary: a table or list of bugs fixed (file → one-line what-was-wrong → fix), each with its test; what was **verified-but-deferred** and why (needs a product call / schema change / `/safe-edit`), tracked in `docs/product/followups.md` where it'll outlive the chat; and the LOW-confidence findings you dismissed with the reason. End with a one-line offer to hunt another surface.

## Tone

- Don't narrate the fan-out or every command — the user reads the diffs and the commit log.
- Be honest about confidence: a fix you proved against the live DB reads differently from a latent guard with no triggering caller — say which.
- Lead with the durable fix; if you ship a narrower one, name the trade-off ([CLAUDE.md](../../CLAUDE.md)).
- 1–2 sentence end-of-turn summary; let the commits speak.
