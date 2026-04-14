-- Enable PostGIS and add spatial search for "popular near me" route discovery.
--
-- Adds a geography(Point) column storing the route's start point, extracted
-- from the first element of the waypoints JSONB array. A spatial index on
-- this column powers ST_DWithin queries for proximity search.
--
-- An RPC function `nearby_routes` wraps the spatial query so clients can
-- call it via supabase.rpc('nearby_routes', { lat, lng, radius_m }) without
-- constructing raw PostGIS SQL.

-- 1. Enable PostGIS (idempotent).
create extension if not exists postgis schema extensions;

-- 2. Add the start-point column.
alter table routes add column start_point geography(Point, 4326);

-- 3. Backfill existing routes from the first waypoint in the JSONB array.
update routes
set start_point = ST_SetSRID(
  ST_MakePoint(
    (waypoints->0->>'lng')::double precision,
    (waypoints->0->>'lat')::double precision
  ),
  4326
)::geography
where jsonb_array_length(waypoints) > 0
  and waypoints->0->>'lng' is not null
  and waypoints->0->>'lat' is not null;

-- 4. Spatial index for proximity queries.
create index routes_start_point_gist on routes using gist (start_point);

-- 5. RPC: find public routes within a radius of a given point, sorted by
--    distance. Returns the same columns as a regular routes SELECT so the
--    client can map the result with the same _routeFromRow / Route type.
create or replace function nearby_routes(
  lat double precision,
  lng double precision,
  radius_m double precision default 50000,
  max_results integer default 50
)
returns setof routes
language sql stable
as $$
  select r.*
  from routes r
  where r.is_public = true
    and r.start_point is not null
    and ST_DWithin(
      r.start_point,
      ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
      radius_m
    )
  order by r.start_point <-> ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
  limit max_results;
$$;

-- 6. Trigger: auto-populate start_point on insert/update from the first
--    waypoint in the JSONB array. Clients never need to construct PostGIS
--    values — they just save waypoints as before.
create or replace function routes_set_start_point()
returns trigger
language plpgsql
as $$
begin
  if jsonb_array_length(NEW.waypoints) > 0
     and NEW.waypoints->0->>'lng' is not null
     and NEW.waypoints->0->>'lat' is not null
  then
    NEW.start_point := ST_SetSRID(
      ST_MakePoint(
        (NEW.waypoints->0->>'lng')::double precision,
        (NEW.waypoints->0->>'lat')::double precision
      ),
      4326
    )::geography;
  end if;
  return NEW;
end;
$$;

create trigger routes_start_point_trigger
  before insert or update of waypoints on routes
  for each row
  execute function routes_set_start_point();
