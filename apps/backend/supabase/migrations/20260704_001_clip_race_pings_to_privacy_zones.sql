-- Drop race_pings inside the runner's privacy zones before they
-- land in the table.
--
-- Closes the audit/public-rows + audit/rls High finding from
-- /audit/all on 2026-05-03: race_pings.lat / .lng broadcast to
-- anyone-who-can-see-the-race, which for a public-club race is
-- anon. Same shape as the live_run_pings leak that was closed in
-- 20260618_001_clip_live_run_pings_to_privacy_zones.sql — the
-- mitigation here is identical.
--
-- A user with privacy zones who participates in a race in a
-- public club therefore broadcasts their actual home / work
-- coordinates to anyone watching the race feed. Casual-privacy v1
-- (decisions §33) was supposed to cover this; this trigger closes
-- the gap by dropping any ping whose coordinates fall inside a
-- configured zone before the row hits the table. The leaderboard
-- aggregate downstream skips the row too — same effect as never
-- broadcasting it.
--
-- Cost: one extra SELECT against user_settings per ping. Race
-- broadcasters tick at single-Hz; negligible compared with the
-- per-row write.
--
-- Trade-off accepted: the runner watching their own race ping
-- feed also won't see in-zone pings. Acceptable — the runner's
-- durable track is still recorded unclipped to Storage for their
-- own /runs/[id] view, and the spectator-feed surface should
-- never carry zone-revealing samples.

create or replace function race_pings_drop_in_zone()
returns trigger
language plpgsql
security definer
-- Need `extensions` on the search path so the call chain into
-- privacy_in_any_zone → privacy_distance_m → PostGIS st_distance /
-- st_makepoint resolves. Same shape as live_run_pings_drop_in_zone.
set search_path = public, extensions
as $$
declare
  v_zones jsonb;
begin
  select prefs->'privacy_zones' into v_zones
    from user_settings where user_id = new.user_id;

  if v_zones is null
     or jsonb_typeof(v_zones) <> 'array'
     or jsonb_array_length(v_zones) = 0
  then
    return new;
  end if;

  if privacy_in_any_zone(new.lat, new.lng, v_zones) then
    return null;
  end if;

  return new;
end;
$$;

create trigger race_pings_drop_in_zone_before_insert
  before insert on race_pings
  for each row execute function race_pings_drop_in_zone();
