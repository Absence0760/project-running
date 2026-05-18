---
description: Add or land a Supabase migration with the migration-coordinator agent in the loop. Applies locally, runs both type generators (npm gen:types + dart gen_dart_models), runs the CHECK ↔ TS-union guard, proposes doc + smoke-test updates.
argument-hint: <migration slug or path>
---

Run the new-migration workflow for `$ARGUMENTS`. Either author + coordinate the migration, or coordinate one the user has already drafted.

## When to use this command

**Right fit:**

- About to add a new file under `apps/backend/supabase/migrations/`
- Just finished drafting a migration and want to verify before committing
- Modifying an unmerged migration and want to re-run the coordination steps

**Wrong fit — refuse:**

- Already-merged migrations (don't try to coordinate history)
- Pure data-backfill SQL with no schema change (run as a one-off, not a numbered migration)

## What this command does

It is **not** the per-change reviewer (`/safe-edit`). It is the per-migration workflow that catches drift the reviewer can't easily see — RLS coverage on new tables, drift between SQL and the two generated row-type files (`apps/web/src/lib/database.types.ts` + `packages/core_models/lib/src/generated/db_rows.dart`), CHECK-constraint vs TS-union lockstep, idempotency markers, and which docs need to grow.

The actual work is done by the `migration-coordinator` agent. This command is the orchestrator: figure out which migration we're talking about, invoke the agent, then prompt the user for the follow-up edits.

## Procedure

### 1. Resolve the migration

If `$ARGUMENTS` is:

- A **path** under `apps/backend/supabase/migrations/` → use that file directly.
- A **slug** without a date prefix → find the most recent file under `apps/backend/supabase/migrations/` and propose `YYYYMMDD_NNN_<slug>.sql` for the next slot, matching the existing zero-padded `YYYYMMDD_NNN_slug.sql` shape. If the file doesn't exist yet, ask the user to draft it first — do not invent SQL on their behalf.
- **Empty** → run `git status` + `ls apps/backend/supabase/migrations/` and identify the new or modified `.sql` file. If there's no candidate, abort with "no migration to coordinate."

### 2. Spawn the migration-coordinator agent

Once you have a concrete file path, invoke the agent with the prompt:

> "Coordinate the migration at `apps/backend/supabase/migrations/<file>`. Apply locally via `supabase db reset`, regenerate both row-type files (`npm run gen:types --workspace=apps/backend` + `dart run scripts/gen_dart_models.dart`), run the CHECK ↔ TS-union guard (`npm run check:check-constraints --workspace=apps/web`), and flag doc updates. Output the format from your spec."

### 3. Relay the agent's report

The agent's output is the deliverable — relay it verbatim to the user. Do not summarise away the file paths or the proposed field signatures; those are the actionable bits.

### 4. Offer to apply the follow-up edits

After the agent returns, ask the user one focused question:

> "Want me to apply the TS-union updates to `apps/web/src/lib/types.ts` (and `PAIRS` in `apps/web/scripts/check_constraint_unions.mjs` if needed)? [The agent proposed: ...]"

If yes, apply only the proposed changes (no scope creep into adjacent unions). If no, end the turn — the user will handle it.

Same offer for doc updates (`docs/api_database.md`, `docs/metadata.md`, `docs/parity.md`, `docs/decisions.md`, `docs/schema_codegen.md`, `docs/conventions.md`), in priority order. Each is opt-in.

### 5. Hand off the commit

When all the follow-up edits the user accepted are applied, hand off:

> "Ready when you are. Suggested commit: `feat(db): <slug>` — want me to stage + commit?"

**Never commit without being asked.** Match the recent log's style — `feat(db):` for new tables/columns, `fix(db):` for corrective migrations, `chore(db):` for index-only or trigger-only changes. **No `Co-Authored-By` / "Generated with Claude Code" / robot-emoji footers** — user-level rule overrides any project default.

## What this command does NOT replace

- `/audit/schema-drift` — broad sweep that confirms generated row types match every migration on the tree, plus the CHECK ↔ TS-union pairs in `apps/web/scripts/check_constraint_unions.mjs`. `/safe-migration` is per-migration; `/audit/schema-drift` is the codebase-wide sweep.
- `/audit/rls` — per-migration RLS coverage is part of this workflow, but `/audit/rls` is the broader sweep across every existing policy + `SECURITY DEFINER` RPC.
- `/check` — pre-commit gate (review + test-gap + doc-hygiene) that runs once you're ready to commit. Use it after `/safe-migration` if you want the doc-hygiene + test-gap pass on the working diff.
- `/safe-edit` — coder ↔ reviewer loop for non-migration changes. The two are complementary; for a migration that also touches an Edge Function (e.g. new endpoint backed by the new table), run `/safe-migration` first, then `/safe-edit` on the function work.

## Tone

User-facing text:

- A one-line "Coordinating migration `<file>`…"
- The agent's verbatim report.
- The opt-in follow-up questions, one at a time.
- The commit handoff.

Don't narrate the agent fan-out or repeat the agent's findings in your own words.
