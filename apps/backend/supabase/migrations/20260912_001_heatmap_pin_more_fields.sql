-- Enrich `clubs_in_bbox` + `discoverable_routes_in_bbox` to return
-- the fields the heatmap popup card needs to show meaningful info:
--   • clubs.location_label — "Richmond, VA" subtitle for the
--     popup so the user knows where the club meets.
--   • routes.elevation_m — elevation gain in metres for the
--     route popup's metadata row alongside distance + surface.
--
-- Both RPCs were sketched in `20260911_001_heatmap_discoverable_pins`
-- with the minimum fields. The May 2026 popup-UX pass asked for a
-- richer card; this migration extends the return signature without
-- changing the WHERE clauses, RLS pattern, or grants.
--
-- `create or replace function` requires the same signature shape;
-- adding columns to RETURNS TABLE is technically a signature
-- change, so we `drop function` first.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

drop function if exists clubs_in_bbox(
  double precision, double precision, double precision, double precision, int
);

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
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
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
    and c.location_point && bbox.g
  order by c.member_count desc, c.created_at desc
  limit p_limit;
$$;

revoke execute on function clubs_in_bbox(
  double precision, double precision, double precision, double precision, int
) from public;

grant execute on function clubs_in_bbox(
  double precision, double precision, double precision, double precision, int
) to anon, authenticated;

drop function if exists discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int
);

create or replace function discoverable_routes_in_bbox(
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
  featured boolean,
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
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
  )
  select
    r.id,
    r.name,
    r.slug,
    r.featured,
    r.distance_m,
    r.elevation_m,
    r.surface,
    r.run_count,
    ST_X(r.start_point::geometry) as lng,
    ST_Y(r.start_point::geometry) as lat
  from routes r, bbox
  where r.is_public = true
    and r.start_point is not null
    and (r.featured = true or r.run_count > 0)
    and r.start_point && bbox.g
  order by r.featured desc, r.run_count desc, r.created_at desc
  limit p_limit;
$$;

revoke execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int
) from public;

grant execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int
) to anon, authenticated;
