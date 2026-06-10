-- Rank only finishers in recompute_event_ranks.
--
-- The rank() window had no partition, so it ranked over EVERY row in
-- the (event_id, instance_start) group — finished, dnf, and dns alike —
-- and the CASE then nulled the rank for non-finishers. But a dnf/dns row
-- carries a duration_s (the column is NOT NULL; a dns is recorded as 0),
-- so it consumed a rank slot in the ordering: with finisher A (1200s),
-- finisher B (1300s) and a dns (0s), the window assigned 1→dns, 2→A,
-- 3→B, leaving the finishers as 2 and 3 with no rank 1.
--
-- Partition the window by (finisher_status = 'finished') so finishers
-- are ranked among themselves starting at 1; non-finishers land in the
-- other partition where the CASE nulls them. Full body re-emitted from
-- the 20260615_001 definition (SECURITY DEFINER + search_path) per the
-- bare-body rule; grants stay as revoked by 20260711_001 (CREATE OR
-- REPLACE preserves them — re-asserted below for safety).

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
          then rank() over (
            partition by (finisher_status = 'finished')
            order by duration_s asc, created_at asc
          )
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

revoke execute on function recompute_event_ranks(uuid, timestamptz) from public, anon;
