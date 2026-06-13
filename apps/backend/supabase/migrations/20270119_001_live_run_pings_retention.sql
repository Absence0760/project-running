-- Widen live_run_pings retention from 4h to 48h to match race_pings.
--
-- The original cleanup (20260509_001) reaped pings older than 4h "longer
-- than any realistic run". That assumption breaks for this app's target
-- workload: every ultra runs longer than 4h, so for a live ultra the cron
-- (cleanup-stale-live-run-pings, 20260602_001, every 15 min) continuously
-- deletes the oldest breadcrumbs WHILE the run is still in progress —
-- truncating the spectator feed mid-run. Worse, a SAR-critical last-known
-- position (the final ping after signal loss) ages out within ~4h, exactly
-- when it matters most.
--
-- The event-keyed sibling race_pings already uses 48h (20261213_001) for
-- the same "scheduled event can run ultra length + spectators replay shortly
-- after" reasons. The two position-ping pipelines must not diverge on
-- retention, so live_run_pings adopts the same 48h window. 48h comfortably
-- brackets any realistic continuous run while still bounding the table's
-- unbounded-growth / cost surface. Pings stay ephemeral: the finisher's own
-- GPS track is stored separately in the runs bucket, so a wider window loses
-- no durable data.
--
-- A retain-until-the-run-ends shape would be more precise, but there is no
-- reliable in-progress/ended signal on runs to drive it (a run row exists
-- from creation; there is no guaranteed live-vs-finished flag), and joining
-- runs into this high-write delete sweep would invent schema for marginal
-- gain. The 48h window directly matches race_pings and fully closes the
-- mid-run-deletion bug, so it is the durable fix here.
--
-- Per the bare-body create-or-replace rule: this writes the COMPLETE desired
-- body (the only change vs 20260509_001 is the 4h -> 48h interval) so no
-- earlier guard is silently dropped. The existing cron job already fires this
-- function by name every 15 minutes; redefining the function in place keeps
-- that single schedule and adds no second conflicting job.

create or replace function cleanup_stale_live_run_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from live_run_pings
   where at < now() - interval '48 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function cleanup_stale_live_run_pings() from public;
grant execute on function cleanup_stale_live_run_pings() to service_role;
