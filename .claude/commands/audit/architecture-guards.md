---
description: Run every source-level architecture-guard test suite + summarize failures
---

Run every architecture-guard test suite across the monorepo and summarize results.

## What this is

The project codifies non-obvious invariants as "architecture guard" tests — fast, source-level (regex / contains) assertions that catch regressions of optimizations and layering rules a linter wouldn't. They're documented in `docs/testing/testing.md` and per-app CLAUDE.md notes.

When one fails, **read the `reason:` block in the test before rubber-stamping a fix** — the failure means a recent change reversed an invariant the codebase deliberately codified.

## Where they live

- `apps/mobile_android/test/architecture_guards_test.dart` — most of them (~33 tests). Includes the `thumbnail privacy-zone clipping` group, `local_run_store` newer-wins guards, sync-paths-batch guards, heavy-parser-isolate guards, lock-screen notification bridge, ErrorWidget.builder boundary, etc.
- `packages/run_recorder/test/architecture_guards_test.dart` — recorder-side invariants (state machine, GPS filter chain).
- `apps/web/src/lib/security_guards.test.ts` — web-side privacy-zone + LRU + fail-closed guards.

## What to do

1. Run each suite and collect output. From the repo root:
   ```
   cd apps/mobile_android && flutter test test/architecture_guards_test.dart
   cd ../../packages/run_recorder && flutter test test/architecture_guards_test.dart
   cd ../../apps/web && npx tsx --test src/lib/security_guards.test.ts
   ```
   (run_recorder's suite imports `package:flutter_test/flutter_test.dart`,
   which pulls in dart:ui types — `dart test` errors with "Offset
   isn't a type" etc. Use `flutter test` so the Flutter SDK provides
   the bindings. Self-audit, May 2026.)
2. For each failing test: print the test name, the `reason:` block from the test source (the WHY), and the assertion message.
3. **Don't fix without instruction.** Each failure is by design a "stop and think" moment.

## Report

- Number of guards passing per suite
- Each failure with its reason block
- A one-line recommendation per failure: "this invariant exists because X; the recent change appears to violate it because Y; talk to the user before fixing"

## Useful starting points

- `apps/mobile_android/CLAUDE.md` § "Tests" — the full list of guard groups
- `docs/testing/testing.md` — the guard-test pattern
- `docs/architecture/conventions.md` — the rules the guards enforce

## Output → `reviews/`

Persist the findings to `reviews/audit-architecture-guards.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
