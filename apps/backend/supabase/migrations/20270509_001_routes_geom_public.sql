-- `routes_within_box` was a membership oracle over the UNCLIPPED
-- `routes.geom` (decisions §33).
--
-- The RPC is granted to `anon` and its response is correctly redacted —
-- it returns `setof public_routes`, which carries no coordinates. But
-- the predicate is `ST_Intersects(r.geom, box)` against the raw
-- polyline, and the response carries `pr.id`. Sweeping a grid of ~10 m
-- boxes and recording which ids come back traces the in-zone tail of a
-- public route at 10 m precision — the same class of leak that
-- `20270504_001` closed on `heatmap_points_in_bbox`, and the one that
-- migration's header explicitly deferred to "a zone-aware `geom_public`
-- column on the `20260925_001` start_point pattern".
--
-- This is that column. `geom_public` is the LineString of exactly the
-- waypoints a NON-OWNER is already allowed to read — the output of
-- `clip_track_for_user`, which is what `clip_route_for_viewer` serves
-- them. Repointing the public spatial predicate at it means a grid
-- sweep can only confirm geometry the caller could already have
-- downloaded, so the oracle carries no new information.
--
-- Maintained by the same trigger pair `20260925_001` uses for
-- `start_point`: a BEFORE trigger on `routes` for waypoint writes, and
-- an AFTER trigger on `user_settings` so adding a privacy zone
-- retroactively re-clips every route the user owns. Registered in
-- `docs/backend/derived_state.md`.
--
-- Fail-closed: `routes_within_box` requires `geom_public is not null`
-- and never falls back to `geom`. A route whose clipped line has fewer
-- than two points (fully inside a zone) drops out of viewport search
-- entirely, exactly as a fully-in-zone route already drops out of
-- `nearby_routes` via the NULL `start_point`.
--
-- `nearby_routes` needs no repoint: its predicate and ordering both run
-- on `start_point`, which `20260925_001` already made zone-aware.

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1. The column. Nullable with no default, so the ADD is a metadata-only
--    flip (no table rewrite) against the populated prod `routes`.
-- ─────────────────────────────────────────────────────────────────────
alter table routes add column geom_public geography(LineString, 4326);

-- ─────────────────────────────────────────────────────────────────────
-- 2. Helper: the privacy-aware LineString for a waypoints array.
--    Delegates the zone walk to `clip_track_for_user` rather than
--    re-implementing it — if the two ever diverged, the public predicate
--    would silently start covering geometry the read path withholds,
--    which is the whole defect this migration closes.
--
--    SECURITY DEFINER because `clip_track_for_user` is revoked from
--    `anon`; the definer context also means the callers below don't
--    depend on the writing role's grants.
-- ─────────────────────────────────────────────────────────────────────
create or replace function privacy_aware_route_geom(
  p_waypoints jsonb,
  p_user_id uuid
)
returns geography
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  clipped jsonb;
  pts geometry[];
begin
  if p_user_id is null then
    return null;
  end if;

  clipped := clip_track_for_user(p_user_id, coalesce(p_waypoints, '[]'::jsonb));

  if clipped is null
     or jsonb_typeof(clipped) <> 'array'
     or jsonb_array_length(clipped) < 2 then
    return null;
  end if;

  -- Same point collection as `routes_set_geom`: entries missing lat/lng
  -- are skipped rather than fatal, so one malformed waypoint can't null
  -- the whole line.
  select array_agg(
           ST_MakePoint(
             (wp.value->>'lng')::double precision,
             (wp.value->>'lat')::double precision
           )
           order by wp.ordinality
         )
    into pts
    from jsonb_array_elements(clipped) with ordinality as wp
   where wp.value->>'lng' is not null
     and wp.value->>'lat' is not null;

  if pts is null or array_length(pts, 1) < 2 then
    return null;
  end if;

  return ST_SetSRID(ST_MakeLine(pts), 4326)::geography;
end;
$$;

revoke execute on function privacy_aware_route_geom(jsonb, uuid)
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Fold `geom_public` into the existing `routes_set_geom` trigger
--    function rather than adding a second trigger, so the two columns
--    can never be written by different code paths and drift.
--
--    Body is the live one from 20260607_001 plus the new assignment;
--    `create or replace` resets proconfig, so the search_path pin from
--    20270415_001 is re-declared here.
-- ─────────────────────────────────────────────────────────────────────
create or replace function routes_set_geom()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  pts geometry[];
begin
  NEW.geom_public := privacy_aware_route_geom(NEW.waypoints, NEW.user_id);

  if NEW.waypoints is null
     or jsonb_array_length(NEW.waypoints) < 2 then
    NEW.geom := null;
    return NEW;
  end if;

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

-- ─────────────────────────────────────────────────────────────────────
-- 4. Extend the user_settings zones trigger to recompute `geom_public`
--    alongside `start_point`, in the SAME update statement — one pass
--    over the user's routes, not two.
--
--    `privacy_aware_route_geom` re-reads `user_settings` through
--    `clip_track_for_user`. That is correct here specifically because
--    this is an AFTER trigger: the updated row is already visible to
--    queries in the trigger body, so the clip runs against the NEW
--    zones, not the old ones. A BEFORE trigger would read the stale row.
-- ─────────────────────────────────────────────────────────────────────
create or replace function user_settings_recompute_route_start_points()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- Cheap short-circuit when privacy_zones didn't change (a typical
  -- user_settings update is a unit-preference flip or a theme change,
  -- not a zones edit).
  if NEW.prefs->'privacy_zones' is not distinct from OLD.prefs->'privacy_zones' then
    return NEW;
  end if;

  update routes
    set start_point = privacy_aware_start_point(
          waypoints,
          NEW.prefs->'privacy_zones'
        ),
        geom_public = privacy_aware_route_geom(waypoints, NEW.user_id)
    where user_id = NEW.user_id;

  return NEW;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Backfill. Keyset-batched over `id` so each UPDATE touches at most
--    500 rows — bounded statement duration and working set against the
--    populated prod table (per docs/backend/migration_locks.md). The
--    Supabase apply path wraps the whole file in one transaction, so the
--    batching bounds each statement rather than splitting the
--    transaction; `routes` is not one of the high-volume tables, so the
--    remaining hold is short.
--
--    Scoped to rows that have a `geom` at all — a route with fewer than
--    two valid waypoints has no public line either, and rewriting it
--    would be a wasted row version.
-- ─────────────────────────────────────────────────────────────────────
do $$
declare
  last_id uuid := '00000000-0000-0000-0000-000000000000';
  batch_max uuid;
begin
  loop
    select max(id) into batch_max
      from (
        select id from routes where id > last_id order by id limit 500
      ) s;
    exit when batch_max is null;

    update routes r
       set geom_public = privacy_aware_route_geom(r.waypoints, r.user_id)
     where r.id > last_id
       and r.id <= batch_max
       and r.geom is not null;

    last_id := batch_max;
  end loop;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6. GIST index so the repointed predicate keeps an index scan. Plain
--    (not CONCURRENTLY): a concurrent build errors inside the wrapped
--    apply transaction, and `routes` is small enough that the write
--    block for the build is short — same call as `routes_geom_gist`.
-- ─────────────────────────────────────────────────────────────────────
create index routes_geom_public_gist on routes using gist (geom_public);

-- ─────────────────────────────────────────────────────────────────────
-- 7. Repoint the public viewport RPC. Body is the live one from
--    20260703_001 with `geom` swapped for `geom_public` in both the
--    predicate and the ordering — no fallback, so a route with no
--    public line is not returned at all.
-- ─────────────────────────────────────────────────────────────────────
create or replace function routes_within_box(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  max_results integer default 50
)
returns setof public_routes
language sql stable security definer
set search_path = public, extensions
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
  select pr.*
  from public_routes pr
  join routes r on r.id = pr.id, box, centre
  where r.geom_public is not null
    and ST_Intersects(r.geom_public, box.g)
  order by r.geom_public <-> centre.g
  limit max_results;
$$;

grant execute on function routes_within_box(
  double precision, double precision, double precision, double precision, integer
) to authenticated, anon;
