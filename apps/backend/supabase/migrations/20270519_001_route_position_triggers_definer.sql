-- A course marker or condition report added by anyone other than the route
-- OWNER silently loses its `position_m`.
--
-- `route_markers_set_position()` (20270129_001) and
-- `route_conditions_set_position()` (20270215_001) are BEFORE-INSERT triggers
-- that read the route's line to derive distance-along-route:
--
--     select geom into v_geom from routes where id = NEW.route_id;
--     if v_geom is null then NEW.position_m := null; return NEW; end if;
--
-- Both are invoker-security. But `routes` base-table RLS has only an owner
-- policy and a club-member SELECT policy — the public-route read policy was
-- dropped by 20260703_001 when public reads moved to the `public_routes` view.
-- Meanwhile both INSERT policies gate on `private.is_route_visible_to(...)`,
-- which IS SECURITY DEFINER and returns true for `is_public = true`.
--
-- So the write is permitted and the read inside the trigger is not. `v_geom`
-- comes back NULL and the function takes its "route has no geometry yet"
-- branch, which is silent by design.
--
-- Verified on the local stack, same route, same lat/lng, one transaction:
--
--     is_route_visible_to(route, viewer)          -> true
--     select count(*) from routes  (as viewer)    -> 0
--     label      | position_m
--     -----------+-----------
--     OwnerAid   | 5558.59
--     ViewerAid  | NULL
--
-- Consequence: 20270428_001 ships viewer contribution as a feature — a race
-- crew member adding "Aid 3 — water only" at km 42 of a public 100-miler. That
-- marker stores position_m NULL, so `sortMarkers` (position_m nulls-last) drops
-- it to the bottom of the course schedule instead of placing it at km 42,
-- `buildRoadbook` cannot put it on the cutoff/leg timeline, and
-- `toRouteGpxWithMarkers` exports it out of order. The route owner adding the
-- identical marker gets the correct value, so it reads as an intermittent bug
-- rather than a permissions one.
--
-- Neither existing test covered the path: the marker suite's position
-- assertion only exercised the OWNER (who can read their own route), and the
-- conditions suite inserts its non-owner report WITHOUT lat/lng, which
-- short-circuits before the routes read. The marker suite now carries a
-- non-owner position assertion, which fails against the pre-fix functions.
--
-- Fix: run both triggers as SECURITY DEFINER, exactly as 20270516_001 did for
-- `event_results_rerank_trigger` against this same class of defect (an RLS
-- read failing inside a trigger fired by a permitted write). The alternative —
-- granting viewers SELECT on `routes` — would expose every base-table column
-- of a public route, which is precisely what the `public_routes` view exists
-- to avoid.
--
-- Both keep `set search_path = public, extensions`; a definer function without
-- a pinned search_path is a hijack vector, and the catch-all audit asserts it.
-- Neither reads anything the caller supplied beyond NEW, and neither writes:
-- they derive one number from the route the caller was already allowed to
-- attach to, so definer adds no authority the INSERT policy hasn't granted.

create or replace function route_markers_set_position()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_geom geography;
  v_frac double precision;
begin
  select geom into v_geom from routes where id = NEW.route_id;

  if v_geom is null then
    NEW.position_m := null;
    return NEW;
  end if;

  v_frac := ST_LineLocatePoint(
    v_geom::geometry,
    ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)
  );
  NEW.position_m := round((v_frac * ST_Length(v_geom))::numeric, 2);
  return NEW;
end;
$$;

create or replace function route_conditions_set_position()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_geom geography;
  v_frac double precision;
begin
  if NEW.lat is null or NEW.lng is null then
    NEW.position_m := null;
    return NEW;
  end if;

  select geom into v_geom from routes where id = NEW.route_id;

  if v_geom is null then
    NEW.position_m := null;
    return NEW;
  end if;

  v_frac := ST_LineLocatePoint(
    v_geom::geometry,
    ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)
  );
  NEW.position_m := round((v_frac * ST_Length(v_geom))::numeric, 2);
  return NEW;
end;
$$;

-- Backfill the rows already written with a null position by a non-owner. Only
-- touches rows that HAVE coordinates but no derived position — a marker on a
-- route with no geometry stays null, which is the legitimate branch.
update route_markers m
set position_m = round(
      (ST_LineLocatePoint(r.geom::geometry, ST_SetSRID(ST_MakePoint(m.lng, m.lat), 4326))
       * ST_Length(r.geom))::numeric, 2)
from routes r
where r.id = m.route_id
  and m.position_m is null
  and m.lat is not null
  and m.lng is not null
  and r.geom is not null;

update route_conditions c
set position_m = round(
      (ST_LineLocatePoint(r.geom::geometry, ST_SetSRID(ST_MakePoint(c.lng, c.lat), 4326))
       * ST_Length(r.geom))::numeric, 2)
from routes r
where r.id = c.route_id
  and c.position_m is null
  and c.lat is not null
  and c.lng is not null
  and r.geom is not null;
