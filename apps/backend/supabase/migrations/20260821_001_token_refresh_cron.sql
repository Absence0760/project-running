-- pg_cron schedule that enqueues a `token_refresh` job hourly so the
-- Go worker (apps/job_worker/internal/handler_token_refresh.go) takes
-- over Strava OAuth rotation from the now-deprecated `refresh-tokens`
-- Edge Function.
--
-- Idempotency:
--   - `cron.schedule(name, ...)` with the same name silently no-ops
--     on Supabase's pg_cron, so re-running this migration is safe.
--   - The cron command itself is dedupe-safe: a fresh `token_refresh`
--     job is only inserted when no queued/running token_refresh row
--     already exists. If the worker is behind, hourly ticks coalesce
--     into a single backlog row instead of multiplying it.
--
-- Operator cutover from the Edge Function:
--   1. Deploy the Go worker (apps/job_worker) with STRAVA_CLIENT_ID +
--      STRAVA_CLIENT_SECRET set as Fly secrets. The boot log should
--      read `strava: enabled (token_refresh dispatch armed)`.
--   2. Apply this migration. The first hourly tick lands within ≤60
--      minutes; `select * from jobs where kind='token_refresh'
--      order by id desc limit 3;` confirms enqueue + drain.
--   3. (Optional) Once steady, retire any dashboard-configured cron
--      that POSTed to the refresh-tokens Edge Function. The EF code
--      itself stays deployed as a rollback path.
--
-- The cron extension is already created by 20260602_001; we just
-- need to schedule the job here.

select cron.schedule(
  'enqueue-token-refresh',
  '0 * * * *',
  $$
    insert into public.jobs (kind, payload)
    select 'token_refresh', '{}'::jsonb
    where not exists (
      select 1 from public.jobs
      where kind = 'token_refresh'
        and status in ('queued', 'running')
    )
  $$
);
