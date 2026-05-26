-- Make `routes.start_point` honour the owner's privacy zones (decisions §33).
--
-- Until now the `routes_set_start_point` trigger populated `start_point`
-- from `waypoints[0]` unconditionally. The `nearby_routes` RPC indexes
-- and searches on that column, so a route built from home surfaced in
-- proximity searches centred near home — the polyline was clipped by
-- `clip_route_for_viewer` but the *dot on the map* wasn't. This is the
-- "routes.start_point leak" called out as a known v1 gap in §33's
-- "trade-offs we're explicitly accepting" list.
--
-- The fix: the trigger now reads the route owner's privacy zones from
-- `user_settings.prefs.privacy_zones` (security-definer indirection
-- because the trigger runs as the writer, which under RLS can't read
-- other-user `user_settings` rows — though for owner-initiated writes
-- the row IS the writer's own, the trigger must still work for
-- service-role writes from imports / Edge Functions), walks the
-- waypoints, and snaps `start_point` to the FIRST waypoint that is
-- NOT inside any zone. If every waypoint is in a zone the column is
-- set to NULL — `nearby_routes` already filters `start_point is not
-- null`, so a fully-in-zone route is hidden from proximity search
-- entirely (the route still renders on its own detail page; only the
-- discovery surface drops it).
--
-- A separate trigger on `user_settings` recomputes `start_point` for
-- every route the user owns whenever their `prefs.privacy_zones`
-- changes — without this, a user who adds a zone AFTER creating
-- routes from home would still leak the old start points until they
-- next saved each route. Same SECURITY DEFINER pattern, same helper.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Helper: compute the privacy-aware start point for a waypoints
--    array given a zones jsonb. Returns geography(Point, 4326) or NULL.
--    Extracted so both the routes trigger and the user_settings trigger
--    use a single implementation.
-- ─────────────────────────────────────────────────────────────────────
create or replace function privacy_aware_start_point(
  p_waypoints jsonb,
  p_zones jsonb
)
returns geography
language plpgsql
immutable
parallel safe
set search_path = public, extensions
as $$
declare
  arr_len int;
  i int;
  pt jsonb;
  pt_lat float;
  pt_lng float;
  has_zones boolean;
begin
  if p_waypoints is null or jsonb_typeof(p_waypoints) <> 'array' then
    return null;
  end if;
  arr_len := jsonb_array_length(p_waypoints);
  if arr_len = 0 then return null; end if;

  has_zones := p_zones is not null
    and jsonb_typeof(p_zones) = 'array'
    and jsonb_array_length(p_zones) > 0;

  -- Find the first waypoint that has valid lat/lng AND (when zones
  -- are configured) is not inside any zone. Returns NULL if every
  -- waypoint is in a zone — `nearby_routes` filters `start_point is
  -- not null`, so the route is dropped from proximity search entirely.
  for i in 0..(arr_len - 1) loop
    pt := p_waypoints -> i;
    if pt->>'lat' is null or pt->>'lng' is null then continue; end if;
    pt_lat := (pt->>'lat')::float;
    pt_lng := (pt->>'lng')::float;
    if has_zones and privacy_in_any_zone(pt_lat, pt_lng, p_zones) then
      continue;
    end if;
    return st_setsrid(st_makepoint(pt_lng, pt_lat), 4326)::geography;
  end loop;

  return null;
end;
$$;

-- Used by the triggers below; not user-facing so no anon/auth grants.
revoke execute on function privacy_aware_start_point(jsonb, jsonb)
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Replace the routes_set_start_point trigger function. Now reads
--    the owner's privacy_zones via SECURITY DEFINER so the trigger
--    works for both owner-initiated writes (where RLS would also let
--    them read their own user_settings) and service-role writes from
--    imports + Edge Functions (which run without an authenticated
--    user but still need to honour the route owner's zones).
-- ─────────────────────────────────────────────────────────────────────
create or replace function routes_set_start_point()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  zones jsonb;
begin
  select prefs->'privacy_zones' into zones
    from user_settings where user_id = NEW.user_id;

  NEW.start_point := privacy_aware_start_point(NEW.waypoints, zones);
  return NEW;
end;
$$;

-- The trigger itself is unchanged (BEFORE INSERT OR UPDATE OF
-- waypoints) — it was created in 20260415_001 and the create-or-
-- replace above swaps out the function body it executes.

-- ─────────────────────────────────────────────────────────────────────
-- 3. New trigger on user_settings: when a user's privacy_zones
--    change, recompute start_point for every route they own. Without
--    this, a user who creates routes from home, THEN adds a privacy
--    zone, keeps leaking the old start points (because the routes
--    trigger only fires on waypoint writes).
-- ─────────────────────────────────────────────────────────────────────
create or replace function user_settings_recompute_route_start_points()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- Cheap short-circuit when privacy_zones didn't change (a typical
  -- user_settings update is a unit-preference flip or a theme change,
  -- not a zones edit).
  if NEW.prefs->'privacy_zones' is not distinct from OLD.prefs->'privacy_zones' then
    return NEW;
  end if;

  update routes
    set start_point = privacy_aware_start_point(
      waypoints,
      NEW.prefs->'privacy_zones'
    )
    where user_id = NEW.user_id;

  return NEW;
end;
$$;

drop trigger if exists user_settings_privacy_zones_trigger on user_settings;
create trigger user_settings_privacy_zones_trigger
  after update of prefs on user_settings
  for each row
  execute function user_settings_recompute_route_start_points();

-- ─────────────────────────────────────────────────────────────────────
-- 4. One-shot backfill: re-compute start_point for every existing
--    route owned by a user who has at least one privacy zone. Routes
--    of users without zones are unaffected (privacy_aware_start_point
--    returns the same waypoints[0] in that case). Cheap — bounded by
--    the count of routes owned by users with zones.
-- ─────────────────────────────────────────────────────────────────────
update routes r
set start_point = privacy_aware_start_point(
  r.waypoints,
  (select prefs->'privacy_zones' from user_settings where user_id = r.user_id)
)
where r.user_id in (
  select user_id from user_settings
  where prefs->'privacy_zones' is not null
    and jsonb_typeof(prefs->'privacy_zones') = 'array'
    and jsonb_array_length(prefs->'privacy_zones') > 0
);
