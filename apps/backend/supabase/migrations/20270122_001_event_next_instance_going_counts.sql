-- Scoped per-event next-instance 'going' count for the events-list enrichment.
--
-- `enrichEvents` (apps/web/src/lib/core/data.ts) needed each event's "Going"
-- headcount at ONLY that event's next instance. It used to fetch every
-- status='going' event_attendees row for the listed events with no limit and
-- tally client-side which rows fell at the next instance — transferring tens
-- of thousands of rows across the wire to produce N integers.
--
-- This RPC pushes the count into the database, mirroring the per-instance
-- count(*) the capacity trigger (20261018_001) already does: each event id is
-- paired with its next-instance timestamp and only attendees at that exact
-- (event_id, instance_start) with status='going' are counted. The
-- (event_id, instance_start) index from 20260417_001 serves it.
--
-- SECURITY INVOKER: the function runs as the caller, so RLS on
-- event_attendees gates row visibility identically to the prior direct select
-- — no privilege escalation.

create or replace function event_next_instance_going_counts(
  p_event_ids uuid[],
  p_next_starts timestamptz[]
)
returns table (event_id uuid, going_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  with pairs as (
    select
      ids.id as event_id,
      starts.next_start as next_start
    from unnest(p_event_ids) with ordinality as ids(id, ord)
    join unnest(p_next_starts) with ordinality as starts(next_start, ord)
      on ids.ord = starts.ord
  )
  select
    p.event_id,
    count(a.user_id) as going_count
  from pairs p
  left join event_attendees a
    on a.event_id = p.event_id
   and a.instance_start = p.next_start
   and a.status = 'going'
  group by p.event_id;
$$;

grant execute on function event_next_instance_going_counts(uuid[], timestamptz[]) to authenticated, anon;
