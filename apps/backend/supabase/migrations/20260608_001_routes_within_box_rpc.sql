-- routes_within_box: viewport-shaped companion to nearby_routes.
--
-- nearby_routes answers "routes whose start is within R metres of a
-- point" — fine for the discovery panel's "near me" feed but wrong for
-- a panning map: a route whose start sits outside the visible viewport
-- but whose body crosses it should still appear. With routes.geom now
-- available (migration 20260607_001) we can answer the bbox question
-- properly via ST_Intersects against the full LineString.
--
-- Returns the same row shape as `routes` so the client maps the
-- result through the existing _routeFromRow / Route plumbing without
-- a new DTO. Sorted by distance from the box centre so the closest
-- routes land first; cap defaults to 50 (same as nearby_routes).

create or replace function routes_within_box(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  max_results integer default 50
)
returns setof routes
language sql stable
as $$
  with box as (
    select ST_SetSRID(
      ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat),
      4326
    )::geography as g
  ),
  centre as (
    select ST_SetSRID(
      ST_MakePoint(
        (min_lng + max_lng) / 2,
        (min_lat + max_lat) / 2
      ),
      4326
    )::geography as g
  )
  select r.*
  from routes r, box, centre
  where r.is_public = true
    and r.geom is not null
    and ST_Intersects(r.geom, box.g)
  order by r.geom <-> centre.g
  limit max_results;
$$;
