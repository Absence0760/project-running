-- `heatmap_points_in_bbox` handed anon the UNCLIPPED route polyline.
--
-- 20260910_001 made the RPC SECURITY DEFINER to fix a "returns 0 rows"
-- regression, and argued there was "no PII leak — waypoints / user_id /
-- club_id never escape the function body … only the densified output
-- points (one per ~50 m)". That reasoning is wrong: the densified output
-- points ARE the waypoints, resampled. `ST_LineInterpolatePoints` walks
-- the whole line, including the stretch inside the owner's privacy zone,
-- and emits the terminal vertex at fraction 1.0.
--
-- So an anonymous caller (the anon key ships in the web bundle) could
-- read a runner's clipped route on /share/route/<id>, note where the
-- polyline stops, POST a ~300 m bbox around that point to this RPC, and
-- get the rest of the line back at 50 m resolution — the walk from the
-- clip boundary to the front door. That is exactly the coordinate §33
-- exists to withhold, and it also undoes 20260925_001, which NULLs
-- `start_point` for a fully-in-zone route so it drops out of proximity
-- search: this reader filters only on `geom is not null`, so those very
-- routes were still rendered here in full.
--
-- Fix: clip inside the function. The zones are read with definer rights
-- (owner-only RLS on `user_settings` would otherwise hide them from the
-- caller) and never leave the body — only the decision to drop a point
-- does. Same helper the other non-owner readers use
-- (`clip_route_for_viewer`, `route_markers_for_viewer`).
--
-- `routes_within_box` reads the same unclipped `geom` in its WHERE
-- clause and remains a slower membership oracle over it; closing that
-- wants a zone-aware `geom_public` column on the `20260925_001`
-- start_point pattern, which is a separate change.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create or replace function heatmap_points_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_max_points integer default 5000
)
returns table (lng double precision, lat double precision)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
  ),
  hit_routes as (
    select r.geom, s.prefs->'privacy_zones' as zones
    from routes r
    left join user_settings s on s.user_id = r.user_id
    cross join bbox
    where r.is_public = true
      and r.geom is not null
      and r.geom && bbox.g
    limit 200
  ),
  densified as (
    select
      (ST_DumpPoints(
        ST_LineInterpolatePoints(
          hr.geom::geometry,
          least(1.0, 50.0 / greatest(ST_Length(hr.geom), 50.0))
        )
      )).geom as pt,
      hr.zones
    from hit_routes hr
  )
  select
    ST_X(pt) as lng,
    ST_Y(pt) as lat
  from densified
  where zones is null
     or not privacy_in_any_zone(ST_Y(pt), ST_X(pt), zones)
  limit p_max_points;
$$;

revoke execute on function heatmap_points_in_bbox(
  double precision, double precision, double precision, double precision, integer
) from public;

grant execute on function heatmap_points_in_bbox(
  double precision, double precision, double precision, double precision, integer
) to anon, authenticated;
