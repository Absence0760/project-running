-- Course markers on a route — aid stations, cutoffs, crew/parking access,
-- hazards / notes / climbs. Lets an owner annotate a saved route line so a
-- race / ultra course (and a club publishing a course) carries the per-point
-- detail the bare geometry can't: an aid station's services, a cutoff's clock
-- time, where crew can park, a hazard or a climb. Greenfield — nothing modelled
-- markers / checkpoints / aid before this.
--
-- Shape decisions (decisions ADR §… route markers):
--   * Own table (not a routes.waypoints field): per-marker rows get their own
--     RLS, index, and a future per-marker photo without bloating the bulk
--     waypoints UPDATE. Mirrors route_photos (20270114_001).
--   * Anchored by a dropped map point (lat/lng). `position_m` — distance along
--     the route from the start — is DERIVED server-side from the route's
--     existing `geom` LineString via a trigger, so the client never computes it
--     and it can't drift from the geometry. "Aid 2 — 31.5 km".
--   * `kind` is a narrow union enforced by a CHECK + mirrored as a TS union
--     (RouteMarkerKind) + a Dart raw string; the (table,column) pair is added to
--     apps/web/scripts/check_constraint_unions.mjs so parity-types guards drift.
--   * `meta` jsonb carries the per-kind extras (aid services[], cutoff
--     clock/elapsed, note text) — documented in docs/features/route_markers.md.
--
-- Visibility: markers FOLLOW the route. Base SELECT is gated by
-- private.is_route_visible_to (owner / public / club member), the same helper
-- route_photos / route_reviews / segments use. The canonical *display* read goes
-- through route_markers_for_viewer() below, which additionally redacts any
-- marker dropped inside one of the owner's privacy zones for non-owner viewers —
-- the marker equivalent of clip_route_for_viewer for waypoints (decisions §33).

-- ─────────────────────── route_markers table ───────────────────────

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create table route_markers (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  kind        text not null
              check (kind in ('aid_station', 'cutoff', 'crew_access',
                              'hazard', 'note', 'climb', 'custom')),
  label       text not null check (length(label) between 1 and 120),
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  position_m  numeric(10, 2),
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index route_markers_route_pos on route_markers (route_id, position_m);

-- ─────────────────── position_m derived from route.geom ───────────────────
-- ST_LineLocatePoint returns the [0,1] fraction of the line nearest the point;
-- multiplying by the geography length (metres on the spheroid) gives distance
-- along the route from the start. Cast geom→geometry for LineLocatePoint (it is
-- planar-only); keep ST_Length on the geography for a true metre length. A route
-- with <2 valid waypoints has no geom yet → leave position_m null (the schedule
-- list falls back to insertion order).
create or replace function route_markers_set_position()
returns trigger
language plpgsql
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

create trigger route_markers_position_trigger
  before insert or update of lat, lng, route_id on route_markers
  for each row execute function route_markers_set_position();

-- ─────────────────── updated_at touch ───────────────────
create or replace function route_markers_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

create trigger route_markers_updated_at_trigger
  before update on route_markers
  for each row execute function route_markers_set_updated_at();

-- ─────────────────────── RLS ───────────────────────
alter table route_markers enable row level security;

create policy "markers readable when route is visible"
  on route_markers for select
  using (private.is_route_visible_to(route_markers.route_id, auth.uid()));

create policy "route owner adds markers"
  on route_markers for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from routes
      where routes.id = route_markers.route_id and routes.user_id = auth.uid()
    )
  );

create policy "route owner updates markers"
  on route_markers for update
  to authenticated
  using (
    exists (
      select 1 from routes
      where routes.id = route_markers.route_id and routes.user_id = auth.uid()
    )
  )
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from routes
      where routes.id = route_markers.route_id and routes.user_id = auth.uid()
    )
  );

create policy "route owner deletes markers"
  on route_markers for delete
  to authenticated
  using (
    exists (
      select 1 from routes
      where routes.id = route_markers.route_id and routes.user_id = auth.uid()
    )
  );

-- ─────────────────── route_markers_for_viewer ───────────────────
-- Canonical display read. Mirrors clip_route_for_viewer: caller passes only the
-- route id, the server decides visibility and redaction. Owner gets every
-- marker; a non-owner gets markers EXCEPT any whose point falls inside one of
-- the owner's privacy zones, so a public course can't leak a pin dropped at the
-- owner's home. Anon callers (auth.uid() null) are non-owner and only reach
-- public routes (raises 42501 otherwise so the surface fails loud).
create or replace function route_markers_for_viewer(p_route_id uuid)
returns setof route_markers
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_caller uuid := auth.uid();
  v_owner  uuid;
  v_zones  jsonb;
begin
  select user_id into v_owner from routes where id = p_route_id;
  if v_owner is null then
    raise exception 'route not found' using errcode = 'P0002';
  end if;

  if not private.is_route_visible_to(p_route_id, v_caller) then
    raise exception 'route not visible' using errcode = '42501';
  end if;

  -- Owner sees everything.
  if v_caller is not null and v_caller = v_owner then
    return query
      select * from route_markers
      where route_id = p_route_id
      order by position_m nulls last, created_at;
    return;
  end if;

  -- Non-owner: drop markers inside the owner's privacy zones.
  select prefs->'privacy_zones' into v_zones
    from user_settings where user_id = v_owner;

  return query
    select * from route_markers
    where route_id = p_route_id
      and not privacy_in_any_zone(lat, lng, v_zones)
    order by position_m nulls last, created_at;
end;
$$;

revoke execute on function route_markers_for_viewer(uuid) from public;
grant execute on function route_markers_for_viewer(uuid) to anon, authenticated, service_role;
