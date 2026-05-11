-- CHECK constraint pinning the set of `jobs.kind` values the Go
-- worker (apps/job_worker) knows how to dispatch. Pre-fix, `kind`
-- was an open-ended `text` column — a typo in a trigger, a stale
-- payload from a future migration that didn't ship a worker handler
-- yet, or an operator-inserted job with the wrong string would all
-- slip through the INSERT and only surface at worker dispatch as
-- `finish_job(failed, "unknown job kind ...")`. The job hangs in
-- the queue at `attempts = max_attempts` and the trigger that
-- enqueued it gets no signal that the work never happened.
--
-- The constraint enforces the same allowlist the Go dispatch switch
-- enforces in `apps/job_worker/internal/worker.go`. Adding a new
-- kind from now on requires (1) extending the Go switch, (2)
-- extending this CHECK in a new migration, and (3) the pgtap suite
-- in `apps/backend/supabase/tests/jobs_kind_allowlist_test.sql`.
-- Same pattern as the narrow-union+CHECK pairs documented in
-- `docs/schema_codegen.md` (RunSource, RouteSurface, etc.) — only
-- here there's no client-side TS/Dart union to keep in sync because
-- `jobs.kind` is worker-only.
--
-- The two kinds wired today:
--   - map_match     (apps/job_worker/internal/worker.go handleMapMatch)
--   - token_refresh (apps/job_worker/internal/handler_token_refresh.go)
--
-- Existing data check: at migration-author time the only kinds in
-- production are `map_match` (run trigger) and `token_refresh` (the
-- 20260821_001 cron schedule). No backfill / data-cleanup is needed
-- because no other value has ever been inserted.

alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh'));
