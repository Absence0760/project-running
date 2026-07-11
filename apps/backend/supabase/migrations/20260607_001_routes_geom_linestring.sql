-- Add full-route geography to `routes` for proper spatial queries.
--
-- The existing `start_point geography(Point, 4326)` (migration
-- 20260415_001) is enough for "route start within radius" lookups but
-- can't answer "routes that pass through this area", "routes that
-- intersect another route", or "routes near a run's track". Storing the
-- full polyline as a `geography(LineString, 4326)` unlocks ST_Intersects /
-- ST_DWithin against the line itself.
--
-- Mirrors the start-point pattern: a trigger keeps `geom` in sync with
-- the canonical `waypoints` jsonb so callers never construct PostGIS
-- values by hand. The Dart codegen emits `geom` as `dynamic` (same as
-- `start_point`), and the TypeScript generator emits `unknown` — both
-- are intentional, since neither client renders the binary EWKB; the
-- column is server-side only.

-- 1. Add the column.
-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

alter table routes add column geom geography(LineString, 4326);

-- 2. Backfill from existing waypoints. Skips routes with fewer than two
--    valid lat/lng pairs — a LineString needs at least two points, and
--    filtering at the source rather than catching exceptions later keeps
--    the migration deterministic. The CTE materialises the per-waypoint
--    points first, then aggregates by route id; a route with 50 invalid
--    waypoints and 2 valid ones still produces a 2-point line rather
--    than failing the whole row.
with valid_points as (
  select
    r.id as route_id,
    wp.ordinality,
    ST_MakePoint(
      (wp.value->>'lng')::double precision,
      (wp.value->>'lat')::double precision
    ) as pt
  from routes r
  cross join lateral jsonb_array_elements(r.waypoints)
    with ordinality as wp
  where wp.value->>'lng' is not null
    and wp.value->>'lat' is not null
),
route_lines as (
  select
    route_id,
    ST_SetSRID(
      ST_MakeLine(pt order by ordinality),
      4326
    )::geography as line
  from valid_points
  group by route_id
  having count(*) >= 2
)
update routes r
set geom = rl.line
from route_lines rl
where r.id = rl.route_id;

-- 3. GIST spatial index. Same shape as `routes_start_point_gist`.
create index routes_geom_gist on routes using gist (geom);

-- 4. Keep `geom` in sync with `waypoints`. Mirrors
--    `routes_set_start_point` so a single client write to `waypoints`
--    populates both columns. Wrapped in a function so the rebuild logic
--    isn't duplicated between insert and update; trigger fires `before`
--    the row hits the table so the populated column lands in the same
--    write.
create or replace function routes_set_geom()
returns trigger
language plpgsql
as $$
declare
  pts geometry[];
begin
  if NEW.waypoints is null
     or jsonb_array_length(NEW.waypoints) < 2 then
    NEW.geom := null;
    return NEW;
  end if;

  -- Collect valid points in waypoint order. Filtering missing lat/lng
  -- here mirrors the migration's backfill behaviour — invalid entries
  -- are skipped, not fatal.
  select array_agg(
           ST_MakePoint(
             (wp.value->>'lng')::double precision,
             (wp.value->>'lat')::double precision
           )
           order by wp.ordinality
         )
    into pts
    from jsonb_array_elements(NEW.waypoints)
      with ordinality as wp
   where wp.value->>'lng' is not null
     and wp.value->>'lat' is not null;

  if pts is null or array_length(pts, 1) < 2 then
    NEW.geom := null;
    return NEW;
  end if;

  NEW.geom := ST_SetSRID(ST_MakeLine(pts), 4326)::geography;
  return NEW;
end;
$$;

create trigger routes_geom_trigger
  before insert or update of waypoints on routes
  for each row
  execute function routes_set_geom();
