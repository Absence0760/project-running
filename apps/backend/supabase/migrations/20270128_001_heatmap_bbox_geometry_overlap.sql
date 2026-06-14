-- Heatmap pin RPCs: use a GEOMETRY bbox overlap, not a geography one.
--
-- clubs_in_bbox (20260912_001) and discoverable_routes_in_bbox
-- (20261114_001) both build the viewport rectangle with
-- `ST_MakeEnvelope(...)::geography` and test `point && bbox`. The `&&`
-- bounding-box-overlap operator on a geography envelope is unreliable
-- once the rectangle gets wide: ST_MakeEnvelope cast to geography spans
-- the rectangle along great-circle edges, so a continental / world-view
-- viewport (the heatmap's initial [0,30] world view, ~360° wide) yields
-- an envelope whose geographic bbox no longer overlaps the pins, and the
-- RPCs return ZERO rows. A narrow city/region viewport happens to work,
-- which masked it.
--
-- Symptoms this fixes:
--   * Zooming the route/club heatmap out to a continental view shows no
--     pins at all (they reappear on zoom-in) — looks broken/empty.
--   * The geolocation-failure "frame the map on the loaded route data"
--     fallback (RouteHeatmap, 401553ff) had no pins to fit to at the
--     world view, so a denied/unavailable locate stranded the user at
--     [0,30] instead of the route data. Pinned by
--     tests-e2e/routes/heatmap.spec.ts "failed locate ... frames the map".
--
-- Fix: drop the `::geography` cast (planar GEOMETRY envelope) and compare
-- against `point::geometry`. A planar bbox overlap is exactly what a map
-- viewport query wants (MapLibre/Leaflet viewports are planar lon/lat
-- rectangles), and it behaves correctly for any rectangle width. Both
-- function bodies are re-emitted whole (the bare-body rule) with every
-- existing filter / distance-band / ordering clause preserved — only the
-- envelope cast + the `&&` operand change. `create or replace` keeps the
-- existing execute grants.

-- ───────────────────────── clubs_in_bbox ─────────────────────────
create or replace function clubs_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit int default 100
)
returns table (
  id uuid,
  name text,
  slug text,
  avatar_url text,
  location_label text,
  member_count int,
  lng double precision,
  lat double precision
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  )
  select
    c.id,
    c.name,
    c.slug,
    c.avatar_url,
    c.location_label,
    c.member_count,
    ST_X(c.location_point::geometry) as lng,
    ST_Y(c.location_point::geometry) as lat
  from clubs c, bbox
  where c.is_public = true
    and c.location_point is not null
    and c.location_point::geometry && bbox.g
  order by c.member_count desc, c.created_at desc
  limit p_limit;
$$;

-- ──────────────────── discoverable_routes_in_bbox ────────────────────
create or replace function discoverable_routes_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit int default 100,
  p_filter text default 'popular',
  p_dist_min numeric[] default null,
  p_dist_max numeric[] default null
)
returns table (
  id uuid,
  name text,
  slug text,
  is_featured boolean,
  distance_m numeric,
  elevation_m numeric,
  surface text,
  run_count int,
  lng double precision,
  lat double precision
)
language sql
stable
parallel safe
security definer
set search_path = public, extensions
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) as g
  )
  select
    r.id,
    r.name,
    r.slug,
    r.is_featured,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.run_count,
    ST_X(r.start_point::geometry) as lng,
    ST_Y(r.start_point::geometry) as lat
  from routes r, bbox
  where r.is_public = true
    and r.start_point is not null
    and r.start_point::geometry && bbox.g
    and case p_filter
      when 'featured' then r.is_featured = true
      when 'friends' then r.user_id in (
        select uf.followee_id from user_follows uf where uf.follower_id = auth.uid()
      )
      when 'hidden_gems' then
        r.is_featured = false and coalesce(r.run_count, 0) = 0 and r.distance_m >= 1000
      else
        (r.is_featured = true or r.run_count > 0)
    end
    and (
      p_dist_min is null
      or cardinality(p_dist_min) = 0
      or exists (
        select 1
        from unnest(p_dist_min, p_dist_max) as band(lo, hi)
        where r.distance_m >= band.lo
          and (band.hi is null or r.distance_m < band.hi)
      )
    )
  order by r.is_featured desc, r.run_count desc, r.created_at desc
  limit p_limit;
$$;
