-- Geocoded region search for clubs.
--
-- Adds `clubs.location_point geography(Point, 4326)` plus a GIST index,
-- and a `search_clubs` RPC that combines ILIKE text matching on the
-- existing `name` / `location_label` columns with optional ST_DWithin
-- geographic filtering. Closes the "search 'Virginia' → no results
-- even though the club's label is 'Richmond, VA'" gap surfaced by the
-- search-scalability audit.
--
-- Client behaviour:
--
--   * `ClubEditor` geocodes `location_label` via MapTiler on save (web)
--     and writes the resulting (lng, lat) into `location_point`. Mobile
--     can adopt the same flow later; until then mobile-saved clubs
--     keep a NULL `location_point` and only surface via the text
--     branch below.
--
--   * `searchClubs(q)` in `data.ts` calls MapTiler's geocoding API for
--     the search string. When it returns a high-confidence place /
--     region result, the client passes the centroid + a radius derived
--     from the bbox to `search_clubs`. Clubs with a `location_point`
--     within that radius surface as geographic matches. Clubs with a
--     NULL `location_point` (legacy / not-yet-geocoded) still surface
--     via the ILIKE branch as before.
--
-- Existing rows have a NULL `location_point` until next save. A
-- server-side backfill is intentionally deferred — Nominatim and
-- MapTiler both have usage policies that bind to a specific client,
-- and dropping ~N geocoding requests into a migration violates both.
-- The natural backfill cadence is "owners re-edit their clubs over
-- time".
--
-- RLS / grants: this migration extends the `20260818_001` column-grant
-- lockdown to include `location_point` as a publicly readable column
-- so the `security invoker` RPC sees it for anon + authenticated
-- callers. The point is not sensitive — it's already represented as a
-- human-readable string in `location_label` for every club that
-- chose to set one.

-- 1. Add the column. Nullable — every existing row stays valid.
alter table clubs add column location_point geography(Point, 4326);

-- 2. Spatial index — partial, since most rows will be NULL for a
--    while as the backfill happens organically through ClubEditor.
create index clubs_location_point_gist
  on clubs using gist (location_point)
  where location_point is not null;

-- 3. Extend the column-grant lockdown from 20260818_001 to include
--    the new column. `revoke select on clubs from authenticated, anon`
--    in that earlier migration deny-by-defaults every column added
--    after it; this grant adds the one new column we just created.
grant select (location_point) on clubs to authenticated, anon;

-- 4. The searcher. Mirrors `search_public_routes` and `nearby_routes`:
--    `setof clubs` so the row mapper on the client doesn't need a new
--    shape, `security invoker` so the existing RLS policies on `clubs`
--    do the visibility gating (caller only sees the rows they're
--    allowed to see).
create or replace function search_clubs(
  p_query text default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m double precision default 80000,  -- ~50mi default; client overrides for region-sized queries
  p_limit int default 60
) returns setof clubs language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select c.*
  from clubs c, center
  where c.is_public = true
    and (
      p_query is null
      or c.name ilike '%' || p_query || '%'
      or c.location_label ilike '%' || p_query || '%'
      or (
        center.pt is not null
        and c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    -- Geographic matches sort by distance ascending; text-only matches
    -- (where the distance is NULL because no center was given OR the
    -- club has no point) fall to the back, ordered by recency.
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    c.created_at desc
  limit p_limit;
$$;

grant execute on function search_clubs(
  text, double precision, double precision, double precision, int
) to authenticated, anon;
