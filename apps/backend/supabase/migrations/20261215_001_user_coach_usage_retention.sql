-- F9: the cleanup_stale_user_coach_usage cron referenced by 20261002_001's
-- comment ("rows roll off via the cleanup_stale_user_coach_usage cron
-- (20260706_001)") was never actually created — 20260706_001 is the MV-refresh
-- migration, not a coach-usage purge. user_coach_usage therefore accumulates one
-- row per (user, UTC day) forever.
--
-- The cap RPCs (increment/get/decrement_coach_usage, 20261002_001) only read a
-- rolling 24h window — today's bucket plus yesterday's if the window straddles
-- UTC midnight — so any bucket older than ~2 days is dead weight. Purge buckets
-- older than 7 days (a generous margin over the 2-day read window) hourly.

create or replace function cleanup_stale_user_coach_usage()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from user_coach_usage
   where usage_date < (now() - interval '7 days')::date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function cleanup_stale_user_coach_usage() from public;
grant execute on function cleanup_stale_user_coach_usage() to service_role;

select cron.schedule(
  'cleanup-stale-user-coach-usage',
  '17 * * * *',
  $$select public.cleanup_stale_user_coach_usage()$$
);
