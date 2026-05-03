-- Privacy-zone clipping for routes (decisions §33).
--
-- Pre-prod privacy-zones audit found six surfaces rendering route
-- waypoints without clipping:
--   web /routes/[id], web /routes "My routes", mobile route_detail_screen,
--   mobile routes_screen, mobile club_detail_screen Routes tab,
--   mobile explore_routes_screen
-- All six render bookmarked / public / club routes the viewer doesn't
-- own. The runs path closed this in 20260523_001_privacy_zone_clipping
-- (clip_track_for_user RPC) and 20260619_001 (drop public Storage
-- policy + clip-public-track EF), but routes were never wired up.
--
-- Routes' waypoints live inline on the row (jsonb column), unlike
-- runs' tracks which sit in Storage. So the fix is just an RPC — no
-- Edge Function indirection needed.
--
-- Shape: clip_route_for_viewer(p_route_id) → jsonb. The function is
-- self-contained (caller passes only the route id), looks up the
-- owner internally via SECURITY DEFINER, applies the same
-- visibility gate as the routes RLS (owner / public / club member),
-- and returns either the unclipped waypoints (owner) or the result
-- of clip_track_for_user against the owner's zones (non-owner).
--
-- This is the route equivalent of the clip-public-track EF for
-- runs: caller never claims ownership, server decides. Anon
-- callers (auth.uid() is null) are non-owner; they can only read
-- public routes (raises 42501 otherwise so the surface is loud,
-- not silent).
--
-- The clip step itself delegates to clip_track_for_user — single
-- implementation of the zone walk, no risk of the routes path
-- drifting from the runs path.
--
-- Also forward-fixes the search_path on the existing privacy
-- helpers from 20260523_001. Their bodies use the geography type
-- (PostGIS), which lives in the `extensions` schema. The helpers
-- were declared `set search_path = public` only — production works
-- because the calling role's default search_path includes
-- extensions, but a direct-SQL caller without that role default
-- (the seed test below, future migrations, ad-hoc psql) hits
-- `type "geography" does not exist`. Fixing the chain in one place
-- avoids the routes path duplicating the search_path workaround.

create or replace function privacy_distance_m(lat1 float, lng1 float, lat2 float, lng2 float)
returns float
language sql
immutable
parallel safe
set search_path = public, extensions
as $$
  select st_distance(
    st_makepoint(lng1, lat1)::geography,
    st_makepoint(lng2, lat2)::geography
  );
$$;

create or replace function privacy_in_any_zone(lat float, lng float, zones_json jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = public, extensions
as $$
declare
  zone jsonb;
begin
  if zones_json is null or jsonb_array_length(zones_json) = 0 then
    return false;
  end if;
  for zone in select * from jsonb_array_elements(zones_json) loop
    if privacy_distance_m(
      lat, lng,
      (zone->>'lat')::float,
      (zone->>'lng')::float
    ) <= (zone->>'radius_m')::float then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

create or replace function clip_route_for_viewer(p_route_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_caller uuid := auth.uid();
  v_owner uuid;
  v_is_public boolean;
  v_club_id uuid;
  v_waypoints jsonb;
  v_visible boolean;
begin
  select user_id, is_public, club_id, waypoints
    into v_owner, v_is_public, v_club_id, v_waypoints
    from routes where id = p_route_id;

  if v_owner is null then
    raise exception 'route not found' using errcode = 'P0002';
  end if;

  -- Visibility gate, mirroring the routes SELECT policies:
  --   - users own their routes (auth.uid() = user_id)
  --   - public routes are readable by anyone (is_public = true)
  --   - club members read club routes (club_id and is_club_member)
  v_visible := (v_caller is not null and v_caller = v_owner)
            or v_is_public = true;
  if not v_visible and v_club_id is not null and v_caller is not null then
    if is_club_member(v_club_id) then
      v_visible := true;
    end if;
  end if;

  if not v_visible then
    raise exception 'route not visible' using errcode = '42501';
  end if;

  -- Owner gets unclipped waypoints.
  if v_caller is not null and v_caller = v_owner then
    return coalesce(v_waypoints, '[]'::jsonb);
  end if;

  -- Non-owner: delegate the zone walk to clip_track_for_user so the
  -- runs and routes paths share one implementation. clip_track_for_user
  -- handles the empty / non-array / oversize cases internally.
  return clip_track_for_user(v_owner, coalesce(v_waypoints, '[]'::jsonb));
end;
$$;

grant execute on function clip_route_for_viewer(uuid) to anon, authenticated;
