-- Drop live_run_pings inside the runner's privacy zones before they
-- land in the table.
--
-- decisions.md §33 says public viewers of /share/run/[id] and
-- /share/route/[id] see clipped tracks; the saved track in
-- Storage is clipped at render time via clip_track_for_user.
-- The live ping feed (Realtime stream backing /live/{run_id}) was
-- not in scope of that ADR — it was rolled out alongside but
-- broadcasts unclipped lat/lng samples to anonymous viewers.
--
-- A user with privacy zones who runs a public-share session
-- therefore broadcasts their actual home / work coordinates over
-- Realtime. Casual-privacy v1 was supposed to cover this case;
-- this trigger closes the gap by dropping any ping whose
-- coordinates fall inside a configured zone before the row hits
-- the table. Realtime fires on table INSERT, so a dropped ping
-- means subscribers receive nothing — same effect as never
-- broadcasting it.
--
-- Cost: one extra SELECT against user_settings per ping. The mobile
-- live broadcaster is throttled to one ping every 5s, so a long run
-- generates ~720/h per runner. Negligible.
--
-- Trade-off accepted: the runner watching their own /live/<id>
-- session also won't see in-zone pings. Acceptable — the surface is
-- for spectators, and the durable track is still recorded
-- unclipped to Storage for the runner's own /runs/[id] view.

create or replace function live_run_pings_drop_in_zone()
returns trigger
language plpgsql
security definer
-- Need `extensions` on the search path so the call chain into
-- privacy_in_any_zone → privacy_distance_m → PostGIS st_distance /
-- st_makepoint resolves. The existing privacy_distance_m doesn't
-- pin its own path, so it inherits ours; pinning to just `public`
-- (the usual safe default) trips '42704: type "geography" does not
-- exist' under SECURITY DEFINER context.
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

create trigger live_run_pings_drop_in_zone_before_insert
  before insert on live_run_pings
  for each row execute function live_run_pings_drop_in_zone();
