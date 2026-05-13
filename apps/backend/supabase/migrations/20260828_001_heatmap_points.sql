-- Popular-route heatmap (parity backlog item #4).
--
-- A public-route discovery overlay: when a runner pans the Explore
-- map, regions where many people have built routes light up. Mirrors
-- the Strava + Komoot "where people actually run" feature, scaled to
-- the route dataset rather than the run dataset because:
--   * routes are deliberately opt-in via `is_public` — no separate
--     heatmap opt-out toggle needed (the user already chose to share
--     when they flipped the route public);
--   * routes already carry a `geom geography(LineString, 4326)`
--     column with a GiST index (migration 20260607_001), so the
--     viewport query is fast;
--   * routes are dense (lots of waypoints per item) and few in
--     number (thousands, not millions) so server-side
//     densification + grouping is cheap.
--
-- Mobile read-path is deferred to v2 — the v1 ships the RPC + the
-- web map overlay only. Per `docs/roadmap.md` parity backlog #4.
--
-- The RPC signature is `(min_lng, min_lat, max_lng, max_lat,
-- max_points)`. It builds an envelope, finds intersecting public
-- routes (capped to 5k via the bbox-narrowing GiST), densifies each
-- line to one point per ~50m via `ST_LineInterpolatePoints`, and
-- streams the resulting points back to the caller. `max_points`
-- bounds the response size so a pan to a continent-wide bbox can't
-- blow the response budget. SECURITY DEFINER not needed — the
-- visibility check is `routes.is_public = true`, which is public
-- information anyway.

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
set search_path = public
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
  ),
  -- Cap the per-route scan early — without this an opportunistic
  -- pan over a dense city can pull in thousands of routes that each
  -- densify to hundreds of points and the response runs into the
  -- multi-MB range. 200 routes × ~25 points each ≈ 5000 cap below.
  hit_routes as (
    select r.geom
    from routes r, bbox
    where r.is_public = true
      and r.geom is not null
      and r.geom && bbox.g
    limit 200
  ),
  densified as (
    select
      (ST_DumpPoints(
        ST_LineInterpolatePoints(
          r.geom::geometry,
          -- Fraction of line length per point. 50 / ST_Length keeps
          -- the inter-point spacing at ~50 metres regardless of the
          -- route's total distance. ST_Length on a geography is
          -- spherical metres so the math is real.
          least(1.0, 50.0 / greatest(ST_Length(r.geom), 50.0))
        )
      )).geom as pt
    from hit_routes r
  )
  select
    ST_X(pt) as lng,
    ST_Y(pt) as lat
  from densified
  limit p_max_points;
$$;

revoke execute on function heatmap_points_in_bbox(
  double precision, double precision, double precision, double precision, integer
) from public;

grant execute on function heatmap_points_in_bbox(
  double precision, double precision, double precision, double precision, integer
) to anon, authenticated;
