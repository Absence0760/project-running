-- The event live-leaderboard derived the "latest ping per runner" set
-- by fetching the newest N race_pings flat (capped at 1000) and folding
-- to one-per-user client-side. In a crowded or long race the cap is
-- spent on the fast front-of-pack runners' high-cadence pings, so a
-- slow back-of-pack runner whose most-recent ping has aged past the
-- 1000-row window falls out of the fold entirely and vanishes from the
-- board — exactly the runner a spectating crew most wants to see.
--
-- This RPC returns one row per runner — their single most-recent ping —
-- so every runner who has ever pinged in the instance is represented
-- regardless of total ping volume. DISTINCT ON (user_id) ORDER BY
-- (user_id, at desc) is served directly by the existing
-- race_pings_by_race_user (event_id, instance_start, user_id, at desc)
-- index, so the per-user latest is a cheap index walk, not a scan.
--
-- SECURITY INVOKER (the default for sql functions) so the caller's RLS
-- on race_pings still applies — the race_pings_visible_when_race_is
-- SELECT policy (which inherits the event-level visibility tightening
-- from 20270113_001 via its exists(... from events ...) chain) is the
-- single gate, identical to the bare-table read this replaces.

create or replace function latest_race_pings(
  p_event_id uuid,
  p_instance_start timestamptz
) returns setof race_pings
language sql
stable
as $$
  select distinct on (user_id) *
  from race_pings
  where event_id = p_event_id
    and instance_start = p_instance_start
  order by user_id, at desc;
$$;

grant execute on function latest_race_pings(uuid, timestamptz) to authenticated, anon;
