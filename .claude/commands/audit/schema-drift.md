---
description: Verify generated TS/Dart row types match migrations + CHECK ↔ TS union pairs are in lockstep
---

Audit codegen drift between Supabase migrations and the two generated row-type files, plus the CHECK-constraint ↔ TS-union pairs documented in `CLAUDE.md`.

## What to check

1. **Run codegen and check for diff.**
   ```
   cd apps/backend && npm run gen:types:check    # TS — fails if out of date
   cd ../.. && dart run scripts/gen_dart_models.dart && git diff --quiet packages/core_models/lib/src/generated/db_rows.dart
   ```
   Either failing means a migration landed without a regen.
2. **CHECK ↔ client vocabularies.** Run `node apps/web/scripts/check_constraint_unions.mjs`, then `node --test apps/web/scripts/check_constraint_unions.test.mjs`. The `PAIRS` array in that script is keyed on `<table>.<column>` and covers **every** live set-shaped CHECK column (67 of them) against **every** client declaration that enumerates it — 121 rails across web TS/Svelte and the Flutter tree (decisions § 791). Any drift means one client can write a value the other rejects (postgres 23514 `check_violation`), or a dropdown silently lacks a value the column admits.
3. **Coverage, not just agreement.** The suite's coverage case asserts the registry equals the live column set exactly. If it fails, a migration added a set-shaped CHECK column without registering it — the guard's own message says which. Do not silence it by deleting the entry for a column that is still there.
4. **Dart parser scope.** The Dart generator only understands `create table`, `alter table ... add column`, `alter table ... drop column`. Anything else (indexes, functions, RLS, storage, `$$..$$` bodies) is silently ignored. Look for recent migrations that use other forms — do any of them add a column the generator missed?
5. **`runs.metadata` jsonb.** No type-level protection on these keys. Cross-check `audit/metadata-keys` for the registry side; this command focuses on column-level drift.

## Report

- **High** — codegen out of date (the actual breakage CI catches).
- **Medium** — CHECK ↔ union mismatch on a real column.
- **Low** — undocumented schema element.

For each: file:line of the migration that introduced the drift, file:line of the generated file that's stale, the command to fix.

## How to fix (only on user request)

```
cd apps/backend && npm run gen:types
cd ../.. && dart run scripts/gen_dart_models.dart
git diff --stat   # confirm only generated files changed
```

The `migration-coordinator` agent automates this for an in-progress migration. Recommend it for the user if drift is from a migration not yet committed.

## Useful starting points

- `docs/architecture/schema_codegen.md` — the canonical workflow
- `apps/web/scripts/check_constraint_unions.mjs` — the CI guard
- `scripts/gen_dart_models.dart` — the Dart generator
- `.claude/agents/migration-coordinator.md` — the diff-time agent
- `CLAUDE.md` § "Schema and row types" — gotchas

## Output → `reviews/`

Persist the findings to `reviews/audit-schema-drift.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
