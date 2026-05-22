-- Fix: `heatmap_points_in_bbox` returns 0 to anon + non-owner
-- authenticated callers.
--
-- Background: the RPC (added in 20260828_001) was SECURITY INVOKER
-- with a comment claiming "SECURITY DEFINER not needed — the
-- visibility check is `routes.is_public = true`, which is public
-- information anyway." That was correct at the time — there was a
-- "public routes are readable by anyone" policy on `routes` that
-- granted anon SELECT for is_public=true rows. Migration
-- 20260703_001_public_routes_view DROPPED that policy as part of
-- the wire-leak guard pass: non-owner callers now reach public
-- routes only via the `public_routes` VIEW (which redacts user_id /
-- club_id) or via the SECURITY DEFINER RPCs in that migration.
--
-- The heatmap RPC was missed in the cleanup: it still does a bare
-- `from routes` read, but anon's RLS view of `routes` is now empty.
-- Result: the heatmap returns 0 points for everyone except the row
-- owner — completely silent failure surfaced only when I added the
-- Virginia seed routes and the local heatmap probe returned zero.
--
-- Fix: mark the RPC SECURITY DEFINER. The function:
--   • reads only `geom` + filters on is_public=true (no PII leak —
--     waypoints/user_id/club_id never escape the function body);
--   • already has `set search_path = public, extensions` so it
--     can't be hijacked via a user-controlled search_path;
--   • already has `execute` granted to anon + authenticated only.
--
-- An alternative would be reading from `public_routes`, but that
-- view doesn't carry `geom` (intentional — the redacted columns
-- are user_id, club_id, slug, waypoints, geom). Adding geom to the
-- view would re-expose the polyline shape, which the wire-leak
-- pass deliberately hid. SECURITY DEFINER on the RPC is the
-- narrower fix: the polyline goes through `ST_LineInterpolatePoints`
-- + `ST_DumpPoints` and only the densified output points (one
-- per ~50m) are returned to the caller — not the raw geometry.

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
