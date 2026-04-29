-- Privacy-zone clipping RPC (decisions.md § 33).
--
-- Public viewers of /share/run/[id] and /share/route/[id] need clipped
-- tracks but must not see the zones themselves. We expose a single
-- SECURITY DEFINER function that reads the owner's
-- user_settings.prefs.privacy_zones, walks the points array, and
-- returns the contiguous middle (drops in-zone leading + trailing
-- points). Zones never leave the database.
--
-- Residual attack: a determined caller can probe the RPC with a dense
-- synthetic point grid and recover zone geometry from the clip output.
-- We mitigate with an input-length cap and accept the residual for
-- the casual-privacy threat model the feature targets (§33).

-- Distance helper. We could roll our own haversine but PostGIS is
-- already enabled for the nearby-routes RPC, so reuse ST_Distance on
-- geography casts — it's exact and does the right thing across the
-- date line.
create or replace function privacy_distance_m(lat1 float, lng1 float, lat2 float, lng2 float)
returns float
language sql
immutable
parallel safe
as $$
  select st_distance(
    st_makepoint(lng1, lat1)::geography,
    st_makepoint(lng2, lat2)::geography
  );
$$;

-- True iff (lat, lng) is within any of the zones in `zones_json`.
-- `zones_json` shape: jsonb array of {lat, lng, radius_m}.
create or replace function privacy_in_any_zone(lat float, lng float, zones_json jsonb)
returns boolean
language plpgsql
immutable
parallel safe
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

-- Clip a points array against the zones of `target_user_id`. Returns
-- the contiguous middle — drops in-zone leading + trailing points but
-- preserves any in-zone points that sit between two out-of-zone
-- points (a loop that returns home mid-run isn't gapped).
--
-- Input cap: 50 000 points. A 5-hour run at 1Hz GPS is ~18k points;
-- 50k gives headroom and bounds the work for the residual probe attack.
create or replace function clip_track_for_user(target_user_id uuid, points jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  zones jsonb;
  arr_len int;
  start_idx int;
  end_idx int;
  i int;
  pt jsonb;
  result jsonb := '[]'::jsonb;
begin
  if points is null or jsonb_typeof(points) <> 'array' then
    return '[]'::jsonb;
  end if;

  arr_len := jsonb_array_length(points);
  if arr_len = 0 then return '[]'::jsonb; end if;
  if arr_len > 50000 then
    raise exception 'clip_track_for_user: input array too large (% points, max 50000)', arr_len;
  end if;

  select prefs->'privacy_zones' into zones
    from user_settings where user_id = target_user_id;

  -- No zones configured → return input unchanged.
  if zones is null or jsonb_typeof(zones) <> 'array' or jsonb_array_length(zones) = 0 then
    return points;
  end if;

  -- Walk forward dropping in-zone leading points.
  start_idx := 0;
  while start_idx < arr_len loop
    pt := points -> start_idx;
    exit when not privacy_in_any_zone(
      (pt->>'lat')::float,
      (pt->>'lng')::float,
      zones
    );
    start_idx := start_idx + 1;
  end loop;

  if start_idx >= arr_len then return '[]'::jsonb; end if;

  -- Walk backward dropping in-zone trailing points.
  end_idx := arr_len - 1;
  while end_idx > start_idx loop
    pt := points -> end_idx;
    exit when not privacy_in_any_zone(
      (pt->>'lat')::float,
      (pt->>'lng')::float,
      zones
    );
    end_idx := end_idx - 1;
  end loop;

  for i in start_idx..end_idx loop
    result := result || jsonb_build_array(points -> i);
  end loop;

  return result;
end;
$$;

-- Allow anon and authenticated callers to use the clipper. RLS on
-- user_settings stays restrictive — the SECURITY DEFINER context is
-- the only path that reads zones, and it returns only the clipped
-- output, never the zones themselves.
grant execute on function clip_track_for_user(uuid, jsonb) to anon, authenticated;
grant execute on function privacy_distance_m(float, float, float, float) to anon, authenticated;
grant execute on function privacy_in_any_zone(float, float, jsonb) to anon, authenticated;
