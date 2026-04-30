-- routes_intersecting_track: find a runner's saved routes whose
-- polyline overlaps an arbitrary track. Concrete consumer of the
-- routes.geom LineString shipped in 20260607_001 — the natural
-- "what saved route did I just run?" question.
--
-- Returns candidates rather than a single best match. The caller
-- (web run-detail page in this commit; mobile + worker later) does
-- the final ranking using the start_offset_m / end_offset_m / route
-- distance fields plus the run's own distance. SQL stays simple;
-- scoring policy stays in the client where it's easy to tune.
--
-- Pre-filter is `ST_DWithin(track, geom, tolerance_m)` so the GIST
-- index on routes_geom_gist drives the scan; without it this would
-- be O(routes-owned-by-user). Tolerance default is 100m, generous
-- enough to absorb GPS jitter on a track that genuinely matches a
-- planned route but tight enough that an entirely different run
-- through the same neighbourhood doesn't match.
--
-- Security: SECURITY INVOKER + the existing `select_own_routes`
-- RLS policy. PostgREST callers see only their own routes; service
-- role (the future Go worker auto-link path) bypasses RLS. The
-- explicit `caller_user_id` filter pairs with RLS rather than
-- replacing it: a malicious client passing a different user_id
-- still hits RLS and gets nothing.

create or replace function routes_intersecting_track(
  caller_user_id uuid,
  track_geojson jsonb,
  tolerance_m double precision default 100,
  max_results int default 10
)
returns table (
  id uuid,
  name text,
  distance_m numeric,
  start_offset_m double precision,
  end_offset_m double precision
)
language sql
stable
security invoker
-- PostGIS lives under the `extensions` schema in Supabase; without
-- including it here the geography type and ST_* functions resolve
-- against an empty search_path and the function fails to compile.
-- Explicit search_path stays as a security-hygiene measure even on
-- INVOKER definers: callers can't shadow `public` symbols with their
-- own schemas at call time.
set search_path = public, extensions
as $$
  with track as (
    select ST_SetSRID(
      ST_GeomFromGeoJSON(track_geojson::text), 4326
    )::geography as g
  ),
  endpoints as (
    select
      ST_StartPoint(t.g::geometry)::geography as a,
      ST_EndPoint(t.g::geometry)::geography as b
    from track t
  )
  select * from (
    select
      r.id,
      r.name,
      r.distance_m,
      ST_Distance(
        ST_StartPoint(r.geom::geometry)::geography,
        e.a
      ) as start_offset_m,
      ST_Distance(
        ST_EndPoint(r.geom::geometry)::geography,
        e.b
      ) as end_offset_m
    from routes r, track t, endpoints e
    where r.user_id = caller_user_id
      and r.geom is not null
      and ST_DWithin(t.g, r.geom, tolerance_m)
  ) candidates
  order by start_offset_m + end_offset_m
  limit max_results;
$$;
