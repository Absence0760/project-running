---
description: Audit Postgres indexing and query patterns — missing / redundant / unused indexes, composite-column ordering, N+1 query shapes, and queries destined to seq-scan as the data grows
---

Audit the schema's indexes (in `apps/backend/supabase/migrations/*.sql`) and the queries that hit them (web `.from(...)` calls, Edge Functions, the `SECURITY DEFINER` RPCs, and `packages/api_client`) for optimization: is every hot path indexed, are there redundant or never-used indexes, are composite indexes column-ordered for the queries that use them, and are any query shapes destined to table-scan as `runs` / `segment_efforts` / `notifications` grow?

## Goal

This is a **query-performance** audit. It asks the question `/audit/db-design` does not: given the schema, *do the queries run fast at scale, and is the index set right-sized*. db-design judges whether the schema is well *modelled* (normalization, FK integrity, constraint coverage, enum design, retention); this judges whether it's well *indexed and queried*. There is deliberate overlap on one line — "missing index on a hot FK" — so **corroborate, don't duplicate**: if `/audit/db-design` or the existing `reviews/audit-db-optimization.md` already named a missing index, reference it rather than re-filing it, and spend the budget here on the things only a query-shape lens catches (composite ordering, redundant/unused indexes, N+1 in application code, predicate/index mismatch).

It is also distinct from `/audit/migration-locks` (whether *adding* an index would block prod) and `/audit/schema-drift` (type sync).

## What to check

1. **Hot paths without a covering index.** Trace the high-frequency reads and confirm each has an index whose leading columns match the `WHERE` + `ORDER BY`:
   - **Feed** — `runs` filtered by owner + visibility, ordered by `started_at DESC`. Confirm a composite like `(user_id, started_at desc)` and a visibility-aware index for the public feed.
   - **Leaderboards** — `segment_efforts` by `segment_id` ordered by `elapsed_seconds`/pace; `personal_records` lookups.
   - **Social** — `run_kudos` / `run_comments` by `run_id`; `user_follows` by both `follower` and `followee` directions (a one-direction index leaves the reverse lookup scanning).
   - **Live** — `live_run_pings` / `race_pings` by session ordered by time (very high write + tail-read).
   - **Notifications** — `notifications` by recipient + unread + time.
   - **Jobs** — `jobs` queue drain by status + scheduled-time (the Go worker polls this hot).
2. **Composite-index column ordering.** A composite index only serves a query whose predicate uses a left-prefix of its columns. Flag indexes whose column order doesn't match the queries that should use them (equality columns first, then the range/sort column), and queries that filter on the *second* column of a composite without the first.
3. **Redundant indexes.** An index on `(a)` is redundant when `(a, b)` exists (the composite already serves `a`-only lookups). Flag redundant pairs — they cost write throughput and bloat for nothing on the high-write tables (`runs`, `live_run_pings`, `segment_efforts`).
4. **Unused / speculative indexes.** Indexes added "to be safe" that no query targets. Where prod access is available the auditor can suggest `pg_stat_user_indexes` (`idx_scan = 0`) as the confirmation step; statically, flag indexes with no matching query in the codebase.
5. **N+1 query shapes in application code.** A loop that fires one query per item instead of a single `in (...)` / join. Sweep web server routes and Edge Functions for `for (… of …) { await supabase.from(...) }` patterns and per-row enrichment. The feed and club surfaces are the usual offenders (fetch runs, then fetch each run's kudos/comments/owner separately).
6. **Queries destined to seq-scan at scale.** `ILIKE '%x%'` on an unindexed text column (search), `ORDER BY` on an unindexed column with a `LIMIT` (sorts the whole table first), `OFFSET` deep-pagination on a big table, JSON path filters into `runs.metadata` with no expression index. Flag each with the table it scans and the row count where it stops being free.
7. **Function/RPC query cost.** The `SECURITY DEFINER` RPCs (`weekly_mileage`, `personal_records` refresh, the trigger-maintained derived caches) run server-side — confirm their internal queries are indexed and that a per-user refresh isn't a whole-table scan. Cross-reference `docs/backend/derived_state.md`.
8. **Materialized views + their refresh.** `mv_weekly_mileage` (refreshed concurrently via pg_cron) — confirm the refresh cadence vs staleness is sane and the view's base query is indexed; a `REFRESH MATERIALIZED VIEW CONCURRENTLY` requires a unique index on the MV.

## Report

- **High** — a hot, user-facing path (feed, leaderboard, notifications, job-queue drain) that seq-scans a large table today or will within the expected data growth; an N+1 on a per-request path; a missing unique index that breaks a concurrent MV refresh.
- **Medium** — a redundant or unused index costing write throughput; a composite mis-ordered for its queries; deep-OFFSET pagination on a growing table; an unindexed `ILIKE`/search path that's currently small.
- **Low** — speculative index with no current query but cheap to keep; a query that's fine now and bounded but worth a note.

For each finding: the index `file:line` or the query `file:line`, the table and its growth profile, *why* it scans / is redundant / is N+1, and the concrete fix (the exact `create index` with correct column order — noting `/audit/migration-locks` governs how to add it safely; the batched/`in(...)` rewrite for an N+1; the index to drop). Where a claim depends on prod row counts or `idx_scan` stats, say so and mark it "confirm against prod stats" rather than asserting.

## Useful starting points

- `apps/backend/supabase/migrations/20260407_001_performance.sql` — the baseline performance-index migration
- `apps/backend/supabase/migrations/20260406_001_database_functions.sql` — `weekly_mileage`, `personal_records`, the RPC bodies to cost
- `apps/backend/supabase/migrations/20260706_001_pg_cron_mv_refresh_15min.sql` — the MV refresh (needs a unique index for CONCURRENTLY)
- `docs/backend/derived_state.md` — the trigger-maintained caches + their authoritative queries
- `apps/web/src/` `.from(...)` call sites (feed, clubs, leaderboards) — N+1 and predicate-vs-index checks
- `packages/api_client/lib/` — the Flutter query layer
- `apps/job_worker/internal/supabase.go` — the job-queue drain query
- `reviews/audit-db-optimization.md` (if present) + `/audit/db-design` output — corroborate overlaps, don't duplicate

## Delegate to

Use the `data-architecture-auditor` agent: `"Audit Postgres indexing and query performance — missing/redundant/unused indexes, composite-column ordering, N+1 query shapes, and seq-scan-at-scale risks across the migrations, web .from() sites, Edge Functions, RPCs, and the Go job worker. Corroborate (don't duplicate) reviews/audit-db-optimization.md and /audit/db-design. Write the report to reviews/audit-db-performance.md."` Read-only on the codebase — recommendations only.

## Output → `reviews/`

Persist findings to `reviews/audit-db-performance.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), one finding per entry with a `[ ]` status box, grouped by severity. If the file exists from a prior run, update it in place (`[x]` resolved with fix commit, `[~]` deferred with reason) rather than overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
