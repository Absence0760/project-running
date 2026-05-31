-- Add a `p_filter` facet to `discoverable_routes_in_bbox` so the
-- route-discovery map can switch the pin set between four lenses
-- instead of always showing the "featured OR run_count > 0" blend.
--
--   • 'popular'      (default) — featured OR has at least one public
--                     run. Identical to the prior hard-coded WHERE, so
--                     every existing caller keeps its behaviour without
--                     passing the new arg.
--   • 'featured'    — admin-curated routes only.
--   • 'friends'     — public routes created by someone the caller
--                     follows (user_follows graph). NOT gated on
--                     popularity: a friend's brand-new route should
--                     surface even with run_count = 0. auth.uid() is
--                     read inside this SECURITY DEFINER body the same
--                     way the run_count trigger reads it; anon callers
--                     get an empty followee set → no rows, which is the
--                     correct fail-closed default.
--   • 'hidden_gems' — public routes nobody has run yet (run_count = 0,
--                     not featured) that clear a sanity floor so the
--                     lens surfaces genuine routes, not 50 m test
--                     scribbles. We have no quality column, so the floor
--                     is distance_m >= 1000 (>= 1 km) on top of the
--                     existing start_point-not-null gate.
--
-- `create or replace function` can't change the argument list, so we
-- drop the prior 5-arg signature first (the previous touch lives in
-- 20260912_001_heatmap_pin_more_fields.sql). The RETURNS TABLE shape,
-- RLS pattern (SECURITY DEFINER + start_point privacy gate), and grants
-- are unchanged.

drop function if exists discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int
);

create or replace function discoverable_routes_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_limit int default 100,
  p_filter text default 'popular'
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
    and r.start_point && bbox.g
    and case p_filter
      when 'featured' then r.featured = true
      when 'friends' then r.user_id in (
        select uf.followee_id from user_follows uf where uf.follower_id = auth.uid()
      )
      when 'hidden_gems' then
        r.featured = false and coalesce(r.run_count, 0) = 0 and r.distance_m >= 1000
      else
        -- 'popular' and any unrecognised value fall back to the
        -- original blend so a stale client can't get an empty map.
        (r.featured = true or r.run_count > 0)
    end
  order by r.featured desc, r.run_count desc, r.created_at desc
  limit p_limit;
$$;

revoke execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int, text
) from public;

grant execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int, text
) to anon, authenticated;
