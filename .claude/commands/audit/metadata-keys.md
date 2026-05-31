---
description: Audit every runs.metadata.<key> read/write across the codebase against docs/backend/metadata.md registry
---

Sweep every `runs.metadata.<key>` access in the codebase and confirm each key is registered in `docs/backend/metadata.md`.

## Goal

`runs.metadata` is a `jsonb` bag with no schema codegen. The only thing keeping cross-platform writers and readers in sync is the registry at `docs/backend/metadata.md`. A typo (`activityType` vs `activity_type`) or a key written by one client and read by another can silently produce a "no data" rendering bug. The pre-existing `metadata_registry_test.dart` catches this at CI time for Dart writers — this command extends that sweep to web + Edge Functions.

## What to check

1. **Web reads/writes.** Grep `apps/web/src/` for `metadata['<key>']`, `metadata.<key>`, `metadata?.<key>`, `metadata: { <key>:`. Collect the unique key set.
2. **Mobile reads/writes.** Grep `apps/mobile_android/lib/` (the iOS twin is byte-identical, so one side is sufficient). Collect.
3. **Edge Function reads/writes.** Grep `apps/backend/supabase/functions/` for the same patterns. Collect.
4. **Registry.** Read `docs/backend/metadata.md`. Extract the registered key list.
5. **Compute drift:**
   - **Unknown writes** — keys written by some client but not in the registry. Either rename to a registered key or document the new key. Both clients writing different cases of the same key (e.g. `activityType` vs `activity_type`) is its own finding.
   - **Dead reads** — registered keys that no client ever reads. Maybe historical, maybe a typo on the read side. Worth flagging.
   - **Dead writes** — registered keys that no client ever writes. Rare but possible (a key only set by a webhook).
   - **Asymmetric writers** — a key written by web only and read by mobile only (or vice versa). Document the contract or fix the asymmetry.

## Report

- **High** — typo / case-mismatch on the same logical key.
- **Medium** — undocumented key, or registered key that's actively out of sync.
- **Low** — dead-key information notes.

For each: the literal key string, the file:line of every reader and writer, the registry status.

## Mitigation

The Dart-side `metadata_registry_test.dart` already enforces "no unknown writes" at CI. Consider growing a sibling test for the web + Edge Functions if a new pattern repeats (the `metadata-key-keeper` agent handles the diff-time enforcement).

## Useful starting points

- `docs/backend/metadata.md` — the registry
- `apps/mobile_android/test/metadata_registry_test.dart` — the existing CI guard for Dart
- `.claude/agents/metadata-key-keeper.md` — the diff-time agent
- `CLAUDE.md` § "Run.metadata is a jsonb bag" — the convention

## Output → `reviews/`

Persist the findings to `reviews/audit-metadata-keys.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
