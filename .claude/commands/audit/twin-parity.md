---
description: Verify apps/mobile_android and apps/mobile_ios lib/+test/ are byte-identical
---

Verify the byte-identical-twin invariant between `apps/mobile_android/` and `apps/mobile_ios/` per `docs/architecture/decisions.md §39`.

## What to do

1. Run `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` and `diff -rq apps/mobile_android/test apps/mobile_ios/test`.
2. If both are clean, report the invariant holds and exit.
3. If either reports differences, list each diverged file. For each:
   - **Differs** — which side has the newer change? Compare commit dates.
   - **Only-in-android / only-in-ios** — was the file added or removed without mirroring?
4. **Don't auto-mirror without instruction.** A divergence may be a deliberate platform-specific code path that someone forgot to wrap with `Platform.isAndroid` / `Platform.isIOS` inside a single shared file. Flag it for the user; recommend either mirroring or re-platform-gating, but ask which.

## Pubspec deltas (allowed)

Per `docs/architecture/decisions.md §39`, the only pubspec differences allowed are `name` and `description`. Run `diff apps/mobile_android/pubspec.yaml apps/mobile_ios/pubspec.yaml` and confirm any other delta is a violation.

## Report format

- Files that differ (with both paths)
- Files only in android
- Files only in ios
- Pubspec deltas beyond `name` + `description`
- The pre-existing `mobile-twin-mirror` agent can be invoked to fix mirroring issues — recommend it for the user.

Read-only by default. The `mobile-twin-mirror` agent is the canonical fixer; this command audits, that agent fixes.

## Useful starting points

- `docs/architecture/decisions.md §39` — the invariant
- `.claude/agents/mobile-twin-mirror.md` — the fixer agent
- `apps/mobile_ios/CLAUDE.md` — twin-specific notes

## Output → `reviews/`

Persist the findings to `reviews/audit-twin-parity.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
