-- Add race-distance filtering to `discoverable_routes_in_bbox` so the
-- discovery map can answer "5k / 10k / half / marathon / ultra routes
-- near here" in any combination.
--
-- The bands are passed as two parallel arrays of bounds —
-- `p_dist_min[i]` .. `p_dist_max[i]` is one band's [lo, hi) window in
-- metres (a NULL hi means open-ended, i.e. ultra). A route matches if
-- it falls inside ANY selected band, so any permutation of bands works
-- (5k OR marathon, half OR ultra, …). The client owns the actual band
-- ranges (apps/web/src/lib/routes/distance_bands.ts) so there is a
-- single source of truth; this function stays generic over whatever
-- windows it is handed. NULL / empty arrays mean "no distance filter".
--
-- This is a bare-body `create or replace`, so the full body — including
-- the p_filter CASE arms from 20261113_001 — is restated here; the only
-- addition is the distance predicate. Drop the prior 6-arg signature
-- first since the argument list grows.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

drop function if exists discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int, text
);

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
        (r.featured = true or r.run_count > 0)
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
  order by r.featured desc, r.run_count desc, r.created_at desc
  limit p_limit;
$$;

revoke execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int, text, numeric[], numeric[]
) from public;

grant execute on function discoverable_routes_in_bbox(
  double precision, double precision, double precision, double precision, int, text, numeric[], numeric[]
) to anon, authenticated;
