-- Align the queued-jobs partial index with claim_next_job's ORDER BY.
--
-- The hot path is the worker's claim query (20260609_001): it filters
-- `status = 'queued' and scheduled_at <= now()` and orders by
-- `scheduled_at, id` — the `id` tie-break makes the FIFO deterministic
-- when a tier-priority burst (20260730_001) enqueues many jobs at the
-- SAME scheduled_at (e.g. a batch of Pro jobs all stamped now()).
--
-- The original `jobs_queued (scheduled_at, kind)` index couldn't serve
-- that ordering: `kind` is not the second sort key, so same-scheduled_at
-- rows came back in index-`kind` order and Postgres had to re-sort them
-- in memory to satisfy `order by scheduled_at, id`. And `kind` bought
-- nothing for the claim path anyway — the worker always claims with an
-- empty kind_filter (job_worker worker.go passes ""), so the equality
-- branch on `kind` is never taken. Kind-scoped lookups that DO exist are
-- served by other indexes: `jobs_dedupe_map_match` (kind, run_id) for the
-- enqueue idempotency check, and `jobs_kind_allowlist` validation is a
-- CHECK, not an index scan.
--
-- Replacing (scheduled_at, kind) with (scheduled_at, id) lets the claim
-- query walk the b-tree in exactly claim order — the LIMIT 1 stops after
-- the first live row with no in-memory sort, even under a same-timestamp
-- burst.
--
-- Lock trade-off: these are plain (non-CONCURRENT) builds. `CREATE INDEX
-- CONCURRENTLY` cannot run through the Supabase CLI migration path — the
-- CLI wraps each migration in a transaction/pipeline and a concurrent
-- build errors with SQLSTATE 25001 ("cannot be executed within a
-- pipeline"), which is why every prior index migration in this repo
-- (20270312_001, 20270316_001, 20270417_001) uses plain CREATE INDEX. A
-- plain build takes a brief ACCESS EXCLUSIVE lock on `jobs` for the build
-- duration. `jobs` is a small, high-churn queue table (the partial index
-- only covers the live `queued` set, which is tiny), so the build is
-- near-instant and the write pause is negligible. For a truly
-- zero-downtime prod build, run the equivalent CONCURRENTLY pair manually
-- in a maintenance window and `supabase migration repair` this version as
-- applied.

create index jobs_queued_v2
  on jobs (scheduled_at, id)
  where status = 'queued';

drop index jobs_queued;
