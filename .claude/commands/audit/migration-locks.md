---
description: Audit production-safety of DDL in apps/backend/supabase/migrations — which migrations take blocking locks or rewrite a table and would cause downtime against the populated prod database
---

Audit `apps/backend/supabase/migrations/*.sql` for online-DDL safety: classify every DDL statement by the Postgres lock it takes and the work it does, and flag the ones that would block writes (or rewrite a table) when `supabase db push` applies them to the live, populated prod database — not the empty local DB where everything is instant.

## Goal

Migrations run on a fresh, tiny local DB (`supabase db reset`) in dev and on the seeded CI stack — both small enough that a table rewrite or an `ACCESS EXCLUSIVE` lock is invisible. Against prod, `runs` is the highest-volume table, with `live_run_pings`, `race_pings`, `segment_efforts`, `run_kudos`, `notifications`, `webhook_events`, and `rate_limits` also growing unboundedly. `supabase db push` applies every pending migration to that live instance. A migration that takes an `ACCESS EXCLUSIVE` lock or rewrites a table there blocks every reader and writer for the duration — that's downtime, and the web app, Edge Functions, and the Go job worker all hit those tables continuously. This audit reads the migrations as a DBA would before a prod apply, judging **lock impact and online-safety**, and nothing else.

This is distinct from `/audit/schema-drift` (generated TS/Dart row types vs migrations; CHECK ↔ TS union lockstep), `/audit/rls` (policy + `SECURITY DEFINER` coverage), and `/audit/db-design` (whether the right index/constraint *should* exist, normalization, FK integrity). **Do not re-report** type-drift, RLS gaps, or whether an index ought to exist — those belong to those audits. Here the question is narrower: given that this DDL runs, *what does it lock, and for how long, against a big table*.

## What to check

Read every `apps/backend/supabase/migrations/*.sql` in version order and classify each DDL statement by lock impact. The specific patterns:

1. **`ADD COLUMN` with a default — constant vs. volatile.** PG11+ adds a column with a *constant* default as a metadata-only change (no rewrite, brief `ACCESS EXCLUSIVE`). An `ADD COLUMN … NOT NULL DEFAULT <literal>` (e.g. the `is_dnf BOOLEAN NOT NULL DEFAULT false` shape in `20261207_001_promote_activity_type_is_dnf.sql`, or `set_count`/`volume` in `20261214_001_gym_workouts_set_count_volume.sql`) hits the fast path — note these as the safe baseline. **Flag any `ADD COLUMN` whose default is *volatile*** (`DEFAULT now()`, `DEFAULT gen_random_uuid()`, a function call, a subquery) against a populated table — those force a full table rewrite under `ACCESS EXCLUSIVE`. `DEFAULT now()` on a column inside a brand-new `CREATE TABLE` is fine (no existing rows); only `ALTER TABLE … ADD COLUMN … DEFAULT now()` against a populated table rewrites.

2. **The add-column / backfill / `SET NOT NULL` sequence.** The canonical multi-step pattern is `ADD COLUMN x … (nullable, fast)` → `UPDATE t SET x = … (whole-table backfill)` → `ALTER TABLE t ALTER COLUMN x SET NOT NULL` (a full sequential scan under `ACCESS EXCLUSIVE` to verify no nulls). `20260417_001_phase2_social.sql` carries a `SET NOT NULL`; check it and any other against table size. On a large `runs`/`segment_efforts`, both the unbatched `UPDATE` and the `SET NOT NULL` scan block. Flag every `SET NOT NULL` on an existing big table and recommend the online form: add a `NOT VALID CHECK (col IS NOT NULL)`, `VALIDATE` it (weaker `SHARE UPDATE EXCLUSIVE` lock), then `SET NOT NULL` (PG12+ skips the scan by trusting the validated constraint).

3. **`ALTER COLUMN … TYPE`.** A type change rewrites the entire table and rebuilds every dependent index under `ACCESS EXCLUSIVE`. None are obvious in the current set — confirm that, and flag any real `ALTER COLUMN … TYPE` against a populated table as **High**, recommending the add-new-column + batched-backfill + swap approach.

4. **`ADD CONSTRAINT` / `ADD FOREIGN KEY` / `ADD … CHECK` without `NOT VALID`.** Adding a CHECK or FK in one step holds a strong lock while it scans every existing row to validate. Several migrations add constraints post-hoc — `20260505_001_narrow_union_check_constraints.sql`, `20261210_001_status_policy_check_constraints.sql`, `20260728_001_cascade_auth_users_fks.sql`, `20261021_001_personal_records_mile_bracket.sql`. For each, check whether it targets a populated table and whether it uses the two-step online form: `ADD CONSTRAINT … NOT VALID` (instant) then `VALIDATE CONSTRAINT` (scans under the weaker `SHARE UPDATE EXCLUSIVE`, lets writes through). Flag single-step constraint adds against big tables. (FK columns declared inline in `CREATE TABLE` are fine — empty table.)

5. **`CREATE INDEX` vs `CREATE INDEX CONCURRENTLY`.** A plain `CREATE INDEX` takes `ACCESS EXCLUSIVE` for the whole build — blocks all writes to the table while it scans. Flag every plain `CREATE [UNIQUE] INDEX` on a large table (`runs`, `segment_efforts`, `run_kudos`, `run_comments`, `live_run_pings`, `notifications`). A `CREATE UNIQUE INDEX` additionally blocks while it checks for existing duplicate keys. The ~47 index definitions across the migration set are the surface here.

6. **`CONCURRENTLY` cannot run inside a transaction block — and Supabase wraps migrations.** `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY` / `REINDEX CONCURRENTLY` error if executed inside any wrapping transaction. **This is the sharpest hazard in this repo**: the Supabase apply path (`supabase db push`) is prone to running a migration file inside a single transaction, which makes any `CONCURRENTLY` DDL in that file fail at apply time. **Verify how this repo's apply path handles transactions** before asserting either way, then: (a) flag any migration that contains `CREATE INDEX CONCURRENTLY` as direct apply-time DDL (it likely needs to be the only statement in its own migration, or applied out-of-band in a maintenance window); (b) note the safe baseline — the only current `CONCURRENTLY` usages are *inside pg_cron `cron.schedule` bodies* (`20260602_001_pg_cron_schedules.sql`, `20260706_001_pg_cron_mv_refresh_15min.sql`: `refresh materialized view concurrently …`), which execute later as scheduled jobs, **not** as apply-time migration DDL — so they're safe today and are the pattern to imitate for deferred concurrent work; (c) note the failed-concurrent-build footgun: a `CONCURRENTLY` build that fails partway leaves an `INVALID` index, and `IF NOT EXISTS` will then *not* rebuild it — needs a manual `DROP INDEX` + retry.

7. **Long-running data backfill inside a migration.** A single unbounded `UPDATE`/`DELETE` over a big table takes row locks on every touched row, bloats the table, and holds those locks for the whole statement. Flag unbatched whole-table DML against `runs`/`segment_efforts`/`notifications` and recommend batching (`… WHERE id BETWEEN $lo AND $hi`, looped). Backfills against small tables (`user_profiles`, `clubs`, `routes` config columns) are low/no concern — note them as such rather than flagging.

8. **`create or replace function` / view rebuilds.** These are metadata-only and cheap, but a `create or replace function` that the backend CLAUDE.md warns about (silently dropping an earlier migration's guard by rewriting a partial body) is a *correctness* concern, not a lock concern — leave it to the function-body gotcha in `apps/backend/CLAUDE.md`. Only flag here if a view/function change forces an `ACCESS EXCLUSIVE` rebuild of a dependent materialized view on a big table.

9. **Lock ordering / multiple objects in one migration.** A migration that takes strong locks on several tables in sequence widens the blocking window and the deadlock surface against concurrent app traffic (the web app + Edge Functions + job worker all write live). Note files that serialize several `ACCESS EXCLUSIVE` operations and would benefit from being split or applied in a maintenance window.

## Report

Group by severity. Tiers for *this* audit are about blast radius against a populated prod table, not correctness:

- **High** — rewrites a table or holds `ACCESS EXCLUSIVE` on a large table (`runs`, `segment_efforts`, `live_run_pings`, `notifications`, `run_kudos`) and would block prod readers/writers for the apply: an `ALTER COLUMN … TYPE`, an `ADD COLUMN` with a volatile default, a `SET NOT NULL` scan, a single-step `ADD CONSTRAINT`/FK validate, a plain (non-`CONCURRENTLY`) index build on a big table, an unbatched whole-table `UPDATE`/`DELETE`, or a `CONCURRENTLY` statement that will error inside the wrapped apply transaction.
- **Medium** — a strong lock that is real but brief or on a smaller/bounded table, avoidable with the online form (a `CREATE UNIQUE INDEX` on a moderate table, a backfill that should be batched but touches a bounded set). Also the `CONCURRENTLY`-inside-a-txn hazard and the failed-concurrent-build / `INVALID` index footgun.
- **Low** — style: a plain `CREATE INDEX` on a table that is and will stay small; a multi-object migration that *could* be split for a tighter lock window.

For each finding: the migration `file:line`, the exact statement, the lock it takes and against which table, what happens when it runs against a populated prod table, and the **safe rewrite** (`NOT VALID` then `VALIDATE`; `CONCURRENTLY` in its own un-wrapped migration; batched backfill loop; add-column-then-swap for a type change). This schema only moves forward — fixes are new `YYYYMMDD_NNN_*.sql`, never edits to applied files; for an already-shipped risky migration, the deliverable is the safe *procedure* to apply it (maintenance window, manual `CONCURRENTLY` step) rather than a code edit.

## Useful starting points

- `apps/backend/supabase/migrations/20260417_001_phase2_social.sql` — carries a `SET NOT NULL` (the add-column / backfill / `SET NOT NULL` lock pattern)
- `apps/backend/supabase/migrations/20260505_001_narrow_union_check_constraints.sql`, `20261210_001_status_policy_check_constraints.sql`, `20260728_001_cascade_auth_users_fks.sql` — post-hoc constraint / FK adds (check for `NOT VALID` + `VALIDATE`)
- `apps/backend/supabase/migrations/20260602_001_pg_cron_schedules.sql`, `20260706_001_pg_cron_mv_refresh_15min.sql` — the only `CONCURRENTLY` usages, deferred inside pg_cron bodies (the safe baseline for concurrent work)
- `apps/backend/supabase/migrations/20261207_001_promote_activity_type_is_dnf.sql`, `20261214_001_gym_workouts_set_count_volume.sql` — `ADD COLUMN … NOT NULL DEFAULT <const>` fast-path baseline to contrast against
- `apps/backend/supabase/migrations/20260407_001_performance.sql` — the index baseline
- `apps/backend/CLAUDE.md` — migration hygiene + the apply path (`supabase db push` to prod, `supabase db reset` locally); confirm the transaction-wrapping behaviour here before judging `CONCURRENTLY`

## Delegate to

Use the `data-architecture-auditor` agent: `"Audit migration lock impact and online-DDL safety across apps/backend/supabase/migrations — classify each statement by Postgres lock and table-rewrite cost against a populated prod table, and flag anything that would block prod. Write the report to reviews/audit-migration-locks.md."` Read-only on the codebase — the deliverable is the findings report with the safe-rewrite per finding, not applied changes. Cross-reference `/safe-migration` and the `migration-coordinator` agent for actually landing the recommended forward fixes.

## Output → `reviews/`

Persist findings to `reviews/audit-migration-locks.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), one finding per entry with a `[ ]` status box, grouped by severity. If the file exists from a prior run, update it in place (`[x]` resolved with the forward-migration commit, `[~]` deferred with reason) rather than overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
