-- pg_cron schedules for periodic maintenance jobs.
--
-- 1. `mv_weekly_mileage` refresh: keeps the dashboard's weekly stats from
--    drifting more than ~5 min behind the underlying `runs` table. Uses
--    `refresh materialized view concurrently` so dashboard reads aren't
--    blocked while the refresh runs (the existing unique index
--    `mv_weekly_mileage_pk` makes concurrent refresh legal).
--
-- 2. `cleanup_stale_live_run_pings()` sweep: the function exists from the
--    20260509_001 migration but had no scheduler attached. Stale pings
--    (>4h old) accumulate when a recording client crashes mid-run; left
--    forever they bloat the table and confuse the spectator view's
--    "where did the runner last appear" hydrate.

create extension if not exists pg_cron;

-- Refresh the dashboard MV every 5 minutes. `concurrently` requires the
-- unique index, which `20260407_001_performance.sql` already creates.
-- Idempotent: `cron.schedule` returns an integer jobid; calling it twice
-- with the same name silently no-ops on Supabase's pg_cron.
select cron.schedule(
  'refresh-mv-weekly-mileage',
  '*/5 * * * *',
  $$refresh materialized view concurrently public.mv_weekly_mileage$$
);

-- Sweep stale live-run pings every 15 minutes. The function itself does
-- the >4h cutoff; this just fires it. 15 min is well below the 4h cutoff
-- and well above the 1 min Postgres-side cron granularity floor — no
-- need to be more aggressive.
select cron.schedule(
  'cleanup-stale-live-run-pings',
  '*/15 * * * *',
  $$select public.cleanup_stale_live_run_pings()$$
);
