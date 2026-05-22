-- Heatmap discoverable-pin RPCs. Two SECURITY DEFINER bbox readers
-- so the /routes?tab=heatmap surface can paint clubs + popular /
-- featured routes alongside the density heatmap layer.
--
-- Both RPCs follow the same shape as `heatmap_points_in_bbox`
-- (migration 20260828_001 + the SECURITY DEFINER fix in
-- 20260910_001) — the post-`20260703_001_public_routes_view`
-- world has no `public routes are readable by anyone` /
-- `public clubs are readable by anyone` SELECT policy on the
-- underlying tables (anon's RLS view of `routes` / `clubs` is
-- empty), so the RPC bypasses RLS with definer rights and returns
-- only explicit redacted fields. No PII / private-club leak: the
-- WHERE clauses gate on `is_public = true` for both, and the
-- columns returned are exactly what the heatmap pin popups need
-- (no owner ids, no descriptions, no full polylines).
--
-- Per-call cap on the result set: 100 by default — enough to fill
-- a viewport at city zoom without sending half the dataset on a
-- world pan. The viewport bbox is the same `ST_MakeEnvelope(...)
-- ::geography && col` trick the existing heatmap RPC uses, so
-- the GiST index on `clubs.location_point` /
-- `routes.start_point` is the load-bearing speed-up.

-- ─────────────────────── clubs_in_bbox ───────────────────────
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

-- ─────────────────────── discoverable_routes_in_bbox ───────────────────────
-- Filter: `featured = true OR run_count > 0`. Featured is admin-
-- curated; run_count > 0 means at least one runner has matched a
-- saved run to this route (the run_match_pipeline path) which is
-- the "popularity" proxy. Both surface routes that are worth
-- discovering; the rest are filed away as "personal route someone
-- saved but isn't a destination yet".
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
