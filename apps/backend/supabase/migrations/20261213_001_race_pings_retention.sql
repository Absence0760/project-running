-- F5: race_pings had no retention purge, only manual admin DELETE via RLS.
--
-- live_run_pings (the run-keyed sibling) has had a cleanup_stale_live_run_pings()
-- function (20260509_001) wired to pg_cron (20260602_001) since launch; race_pings
-- (the event-instance-keyed twin) was never given the equivalent. High-write
-- position-ping tables are the classic unbounded-growth + cost surprise, so the
-- two pipelines must not diverge on retention — this closes the gap.
--
-- Cutoff is 48h (vs 4h for live_run_pings): a race is a scheduled group event
-- that can run ultra length, and spectators may replay shortly after the
-- cutoff, so the window is wider than the solo live-run case. Pings are
-- ephemeral spectator breadcrumbs — the finisher's own GPS track is stored
-- separately in the runs bucket, so purging old pings loses no durable data.

create or replace function cleanup_stale_race_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from race_pings
   where at < now() - interval '48 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function cleanup_stale_race_pings() from public;
grant execute on function cleanup_stale_race_pings() to service_role;

-- Sweep every 30 minutes — well below the 48h cutoff, well above the
-- 1-minute pg_cron floor. Idempotent: re-scheduling the same name no-ops.
select cron.schedule(
  'cleanup-stale-race-pings',
  '*/30 * * * *',
  $$select public.cleanup_stale_race_pings()$$
);
