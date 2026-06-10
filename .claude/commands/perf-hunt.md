---
description: Run rounds of performance hunting on a surface — fan out read-only hunters, triage by measured impact, verify the cost, then fix the real hot spots at the root cause with a regression guard in the same commit. The "find and kill waste" loop.
argument-hint: [surface or area — optional; e.g. "the recording hot path", "dashboard rebuilds", "core/data.ts queries", "LocalRunStore", "web bundle". Omit to let the command pick a surface.]
---

Hunt for **performance defects** on a surface — code that's *correct but slow or wasteful* — then fix the real hot spots at the root cause, each with a regression guard in the same commit. Target: `$ARGUMENTS` (if empty, pick a surface that hasn't been swept recently and say which before hunting).

This is the performance sibling of `/bug-hunt`: **hunt → triage by impact → measure the cost → fix the root cause → pin with a guard → commit per piece → report.**

## When to use this command

**Right fit:**
- "Find and fix perf problems / make X faster" with latitude to choose targets.
- Sweeping a surface for waste: GPS-rate rebuild churn, N+1 query shapes, unbounded memory growth on long runs / large histories, O(n²) on big inputs, redundant fetches, bundle bloat.
- Hardening the recording stack or a data-heavy screen before it has to scale (100-hour ultra tracks, 200+ run windows, a club with thousands of members).

**Wrong fit — do something else instead:**
- *Wrong output* (not just slow) → `/bug-hunt` (correctness is its axis; this loop assumes behaviour is already correct).
- A DB-only indexing question you just want *reported* → `audit:db-performance` (read-only). Use this loop when you intend to **fix**.
- A new capability or a UX gap → `/improve-round`. A perf fix changes *how fast*, not *what it does*.
- A single risky rewrite (a query that feeds RLS, a schema/index migration) → `/safe-edit` / `/safe-migration`.

## What counts as a perf defect (the triage bar)

A finding is worth fixing when **both** hold:
1. There's a **plausible real-world input** at which it bites — a long run, a big history, a hot per-tick path, a populated prod table. "Could be slow with a billion rows" is not a finding; "rebuilds the whole map subtree every GPS fix" is.
2. The fix is **net-positive**, not a micro-optimisation that trades clarity for nanoseconds. Readability is a feature; don't inline a helper or hand-unroll a loop for an unmeasurable win.

Rank survivors by **measured/estimated impact** (how often the path runs × how much it costs × how it grows with data). Fix the top ones. **Premature optimisation is itself the anti-pattern** — if you can't name the input that makes it hurt, leave it with a note.

## Known perf contracts in this repo (don't regress these — extend them)

This codebase already invests in performance and **pins the wins as source-level guards** — read these before hunting so you recognise an intentional optimisation vs a regression:
- **Recording hot path** (`run_screen.dart`): the per-second `_onSnapshot` must NOT `setState` — it publishes to a `ValueNotifier<_LiveStats>` and only the affected subtrees (`ValueListenableBuilder`) rebuild. New per-tick stats go behind the notifier, never a `setState`.
- **Heavy parsers in isolates** ([decisions §48](../../docs/architecture/decisions.md)): Strava/Garmin import + backup encode/decode + route parse run in `compute()`, never on the UI thread. Pinned by `architecture_guards_test.dart`.
- **Windowed stores** ([decisions §135](../../docs/architecture/decisions.md)): `LocalRunStore` cold-loads a track-less `index.json` summary + a resident window of full runs; don't reintroduce a full-history read of `runs` (use `summaries`/`summaryRuns`). `local_activities.dart` caps each source *before* building rows (bounded-build).
- **Derived-state caches** ([derived_state.md](../../docs/backend/derived_state.md)): PRs, route `run_count`, gym totals, coach usage are trigger-maintained so reads are flat-column, not correlated subqueries. A perf fix that adds a cache must follow the cache=authoritative-recompute contract and a rebuild path.
- **Route-builder segment cache** ([decisions §136](../../docs/architecture/decisions.md)): re-routing after one waypoint fetches only the new segment. **Notification refresh throttling**, rolling HR sums (O(1) not O(n)), and `TrackWriter` disk-streaming are the watch-side equivalents.

The bar a fix is held to is the same as those guards: make it faster **and** add the test that stops the regression from coming back.

## The loop

### 1. Pick the surface (if `$ARGUMENTS` is empty or vague)

Choose one bounded surface with real cost potential and say which + why. Good surfaces this repo rewards: the recording hot path (`run_screen.dart` / `packages/run_recorder/`), data-heavy screens (`dashboard_screen.dart`, history/timeline, feed), the Supabase query layer (`core/data.ts` + the RPCs), the offline stores (`LocalRunStore` / `LocalGymStore` / `LocalFoodStore`), the web bundle, the Go worker's per-job allocation. Don't re-sweep a surface you just cleaned.

### 2. Fan out read-only hunters (in parallel)

Spawn hunters in a single message so they run concurrently — `general-purpose` agents, each pointed at a named file list, instructed to find **performance** defects, not correctness or style:
- **Client render**: `setState` (Flutter) / reactive (`$derived`/`$effect`, Svelte) churn on hot paths; rebuilding a whole subtree when a leaf changed; work in `build()` that should be memoised; per-frame allocation.
- **Data shape**: N+1 query patterns (a fetch inside a loop / per-row), over-fetching columns or rows a view doesn't need, `select *` where a projection would do, a client-side filter that should be a server `WHERE`, a missing index on a column the query filters/sorts (cross-check `audit:db-performance` territory but here you'll fix it via `/safe-migration`).
- **Growth with data**: O(n²) scans, full-history reads where a window exists, unbounded in-memory accumulation over a long run / large list, a list re-sorted on every change.
- **Redundancy**: duplicate fetches, work repeated per tick that could be cached, a request not de-duped/throttled.

For each finding: `file:line`, the **input that makes it hurt** (the run length / row count / tick rate), the cost (allocation / wall-clock / query count / how it scales), and confidence. Read the code yourself in parallel.

### 3. Measure or estimate the cost before touching code

Don't fix a perf finding you haven't sized:
- **Name the input** that triggers it and estimate the cost at realistic scale (a 6-hour ultra ≈ 21,600 GPS fixes; a heavy user ≈ thousands of runs; a populated club).
- **For DB findings, prove it against the running stack**: `EXPLAIN (ANALYZE, BUFFERS)` on `127.0.0.1:54322` to confirm a seq scan / bad plan, and re-run after the fix to confirm the plan improved. Seed enough rows that the planner doesn't just pick a seq scan because the table is tiny.
- **For client findings**, confirm the path's frequency (per-tick vs per-navigation) — a per-navigation cost rarely justifies a fix; a per-GPS-fix one almost always does.
- If the measured cost is negligible at realistic scale, **drop the finding with a one-line note** rather than ship a clarity-for-nanoseconds change.

### 4. Escalate the risky ones — don't rush them

If the fix touches a **query feeding an RLS policy, a schema/index migration, a security boundary, or the recording state machine**, route it through `/safe-migration` (DDL) or `/safe-edit` (coder↔reviewer loop) rather than a rapid commit. An index that changes a query plan on the populated prod table, or a "cache" that drifts from its source, is exactly where a careless perf fix becomes a correctness bug.

### 5. Fix the root cause + pin it, one fix per commit

Per [CLAUDE.md § Commit cadence](../../CLAUDE.md), each fix is its own commit with its guard in the **same** commit:
- **Fix the root cause** (move the work off the hot path, project the query, window the read, add the cache + its rebuild) — don't just shave a constant.
- **Pin it so the regression can't return.** Prefer a **source-level guard** in the style this repo already uses (`architecture_guards_test.dart`: "no `setState` in `_onSnapshot`", "import dispatches to `compute()`", "store `_loadAll` keeps the windowed read") — that's how perf wins survive refactors here. Where a guard can't express it, a unit test that asserts the bounded shape (e.g. "rebuild is O(limit), not O(history)") or an `EXPLAIN` assertion. Read the `reason:` on an existing guard before adding a sibling.
- **Twin parity**: any `apps/mobile_android/lib/`+`test/` edit mirrors to `apps/mobile_ios` byte-for-byte (`mobile-twin-mirror`); a TS↔Dart parity-pair edit runs `shared-library-syncer`.
- **Docs**: a new cache → register it in [derived_state.md](../../docs/backend/derived_state.md); a non-obvious trade-off (perf vs memory vs clarity) → one paragraph in [decisions.md](../../docs/architecture/decisions.md); update any doc whose described behaviour changed ([CLAUDE.md § Docs hygiene](../../CLAUDE.md)).

**Commit discipline (shared working tree — [CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)):**
- Always path-scoped: `git commit -m "…" -- path1 path2 …`. `git add <new-file>` for new files only; never `git add -A`/`-u`, never a bare `git commit`.
- One fix = one commit. `git status` before each; confirm every path is yours.
- No AI attribution / `Co-Authored-By` / robot footer (user-level rule). Commit only — never `git push` without an explicit ask.

### 6. Report

Short summary: a list of hot spots fixed (file → what was wasteful + the input that made it hurt → the fix → before/after cost where you measured it), each with its guard; what was **deferred** and why (needs `/safe-migration` / a product call / not worth it at current scale), tracked in `docs/product/followups.md`; and the findings you dismissed as premature with the reason. End with a one-line offer to hunt another surface.

## Tone

- Don't narrate the fan-out — the user reads the diffs and the commit log.
- **Quantify.** "Cuts the per-tick rebuild from the whole Stack to one `ValueListenableBuilder`" or "EXPLAIN went seq-scan → index scan, 18k→40 rows" beats "made it faster".
- Be honest about whether you measured the win or estimated it — say which.
- Lead with the durable fix; if you ship a narrower one, name the trade-off. 1–2 sentence end-of-turn summary; let the commits speak.
