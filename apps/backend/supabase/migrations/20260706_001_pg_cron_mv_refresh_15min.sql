-- Bump mv_weekly_mileage refresh cadence: 5 min → 15 min.
--
-- The dashboard's weekly stats don't need sub-5-minute freshness;
-- users open the page once a session and a 10-minute upper bound on
-- staleness is invisible. The MV refresh dominates background compute
-- on a small Supabase tier, so dropping the rate by 3x is a free
-- spend reduction. Matches the cadence of the live-run pings cleanup.
--
-- pg_cron's `cron.unschedule(text)` raises if the job doesn't exist;
-- guard with a lookup against `cron.job` so the migration is safe to
-- replay against a database that's never had the original schedule.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'refresh-mv-weekly-mileage') then
    perform cron.unschedule('refresh-mv-weekly-mileage');
  end if;
end $$;

select cron.schedule(
  'refresh-mv-weekly-mileage',
  '*/15 * * * *',
  $$refresh materialized view concurrently public.mv_weekly_mileage$$
);
