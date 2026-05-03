-- Mark recompute_event_ranks as SECURITY DEFINER so it actually
-- recomputes the whole (event_id, instance_start) group on every
-- write — not just the rows the caller's RLS allows them to UPDATE.
--
-- Original (20260424_001) was language plpgsql with no security
-- clause — i.e. INVOKER. The trigger fires after any
-- insert/update/delete on event_results and tries to bulk-update
-- `rank` across every row in the group. But the event_results
-- UPDATE policy only allows the row owner OR the event director to
-- write, so a regular athlete inserting their own result rolls
-- through every other competitor's row in the bulk update, gets
-- silently RLS-filtered out, and leaves their ranks stale.
-- Leaderboards only refreshed correctly when a director happened
-- to write.
--
-- Same fix shape that routes_run_count_trigger got in 20260427_001:
-- mark the recompute SECURITY DEFINER + pin search_path. The
-- trigger function around it stays INVOKER; only the inner bulk
-- update needs the elevation.

create or replace function recompute_event_ranks(
  p_event_id uuid,
  p_instance_start timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with ranked as (
    select
      ctid,
      case
        when finisher_status = 'finished'
          then rank() over (order by duration_s asc, created_at asc)
        else null
      end as new_rank
    from event_results
    where event_id = p_event_id and instance_start = p_instance_start
  )
  update event_results er
  set rank = ranked.new_rank,
      updated_at = now()
  from ranked
  where er.ctid = ranked.ctid
    and er.rank is distinct from ranked.new_rank;
end;
$$;
