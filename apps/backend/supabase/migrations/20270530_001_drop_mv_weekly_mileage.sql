-- Drop mv_weekly_mileage, its unique index and its pg_cron refresh.
--
-- The matview was provisioned ahead of need in `20260407_001_performance.sql`
-- and never acquired a reader. `20260517_001` already recorded "zero callers"
-- when it revoked SELECT from anon/authenticated, and nothing has wired one
-- since: no client, RPC, Edge Function or Go worker selects from it. The
-- `weekly_mileage()` RPC that docs/backend/api_database.md claimed reads it
-- aggregates `runs` directly (`20260406_001`, re-emitted in `20260710_001`)
-- and itself has no caller; the dashboard's weekly chart selects a bounded
-- 14-week `(started_at, distance_m)` window off `runs_user_started_at` and
-- buckets it client-side in `bucketWeeklyMileage`, and the "This Week" strip
-- reads runs already in memory. So the refresh is 96 full-table GROUP BYs a
-- day serving zero reads.
--
-- Wiring a SECURITY DEFINER reader was the alternative and is not viable
-- against this matview's shape: `date_trunc('week', ...)` is always ISO
-- Monday-start, so it cannot answer the Sunday-start `week_start_day`
-- preference both dashboards honour; `started_at` is timestamptz, so the
-- bucket boundary falls at the session timezone's midnight (UTC under
-- PostgREST) rather than the runner's local midnight; and the aggregate is
-- unfiltered over all history, where every surface windows and filters. A
-- correct pre-aggregation would have to be keyed per user timezone and per
-- week-start preference, which is a different object, not a wrapper over this
-- one. Dropping is therefore the durable move; the day a genuinely hot
-- weekly aggregate appears, it gets a matview built to that shape.
--
-- Lock profile: `cron.unschedule` writes one row of the small `cron.job`
-- table, and `drop materialized view` takes ACCESS EXCLUSIVE on the matview
-- alone (its index is dropped with it). Neither touches `runs`. No CASCADE,
-- deliberately: nothing depends on the matview today and a fail-loud drop is
-- what should happen if that ever stops being true.
--
-- `cron.unschedule(text)` raises when the job is absent, so guard the lookup
-- the way `20260706_001` did, keeping the migration replayable against a
-- database that never carried the schedule.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'refresh-mv-weekly-mileage') then
    perform cron.unschedule('refresh-mv-weekly-mileage');
  end if;
end $$;

drop materialized view if exists public.mv_weekly_mileage;
