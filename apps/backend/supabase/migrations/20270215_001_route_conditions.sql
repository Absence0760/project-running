-- Community route condition reports — "creek crossing flooded", "trail closed
-- for logging", "ice on the north face". Lets any runner who can see a saved
-- route attach a freshness-stamped, severity-graded note so the next runner
-- knows what they'll hit before they go. Backlog #5 (trail / offline nav) —
-- the community-sourced condition layer alongside the offline tile packs and
-- turn-by-turn cues built in the same slice (decisions §168).
--
-- Shape decisions (decisions ADR §168, route conditions):
--   * Own table (not a routes.* jsonb field): per-report rows get their own
--     RLS, freshness index, and the visibility-gated INSERT that lets ANY
--     viewer of a route — not just its owner — file a report. Mirrors
--     route_reviews (20260414_001 + the 20260627_001 insert-gate) rather than
--     route_markers, which is owner-only.
--   * `condition` + `severity` are narrow unions enforced by CHECK + mirrored
--     as TS unions (RouteConditionKind / RouteConditionSeverity) + Dart raw
--     strings; both (table,column) pairs are added to
--     apps/web/scripts/check_constraint_unions.mjs so parity-types guards drift.
--   * An OPTIONAL anchor point (lat/lng) lets a report pin "flooded at 4.2 km".
--     `position_m` — distance along the route — is DERIVED server-side from the
--     route's geom via a trigger (same as route_markers), guarded for null
--     lat/lng (an unanchored report leaves position_m null).
--   * `note` is bounded 1..500 chars when present (free text is the value).
--
-- Visibility: reports FOLLOW the route. Base SELECT is gated by
-- private.is_route_visible_to (owner / public / club member). The canonical
-- display read goes through route_conditions_for_viewer() below, which
-- additionally redacts the lat/lng of any anchored report inside one of the
-- route owner's privacy zones for non-owner viewers — the condition analogue
-- of route_markers_for_viewer / clip_route_for_viewer (decisions §33).
--
-- Spam cleanup: a report's author can delete it; ADDITIONALLY the ROUTE OWNER
-- can delete any report on their own route (mirrors the 20260627_001 rationale
-- — the owner needs to clean up a bad report even though they didn't write it).

-- ─────────────────────── route_conditions table ───────────────────────

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create table route_conditions (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  condition   text not null
              check (condition in ('clear', 'muddy', 'flooded', 'snow_ice',
                                   'overgrown', 'closed', 'hazard', 'other')),
  severity    text not null default 'info'
              check (severity in ('info', 'caution', 'impassable')),
  note        text check (note is null or length(note) between 1 and 500),
  lat         double precision check (lat is null or lat between -90 and 90),
  lng         double precision check (lng is null or lng between -180 and 180),
  position_m  numeric(10, 2),
  created_at  timestamptz not null default now()
);

create index route_conditions_route_recent
  on route_conditions (route_id, created_at desc);

-- ─────────────────── position_m derived from route.geom ───────────────────
-- Copy of route_markers_set_position (20270129_001) guarded for the optional
-- anchor: a report with no lat/lng (an unanchored "trail closed" note that
-- applies to the whole route) leaves position_m null. ST_LineLocatePoint is
-- planar-only so cast geom→geometry; keep ST_Length on the geography for a true
-- metre length.
create or replace function route_conditions_set_position()
returns trigger
language plpgsql
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

create trigger route_conditions_position_trigger
  before insert or update of lat, lng, route_id on route_conditions
  for each row execute function route_conditions_set_position();

-- ─────────────────────── RLS ───────────────────────
alter table route_conditions enable row level security;

create policy "conditions readable when route is visible"
  on route_conditions for select
  using (private.is_route_visible_to(route_conditions.route_id, auth.uid()));

-- Author reads their own report even if the route flips public→private after
-- they filed it (matches the route_reviews owner-self read in 20260627_001).
create policy "users read their own conditions"
  on route_conditions for select
  to authenticated
  using (auth.uid() = user_id);

-- Visibility-gated INSERT: any signed-in viewer of the route can report. The
-- `routes` subquery picks up RLS on routes automatically, so the writer can
-- only report a route they can SELECT (own / public / club-readable) — blocks
-- planting rows against an enumerated private route id.
create policy "users report conditions on visible routes"
  on route_conditions for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from routes where routes.id = route_conditions.route_id
    )
  );

create policy "users update their own conditions"
  on route_conditions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- DELETE: the author OR the route owner (spam cleanup on one's own route).
create policy "author or route owner deletes conditions"
  on route_conditions for delete
  to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1 from routes
      where routes.id = route_conditions.route_id and routes.user_id = auth.uid()
    )
  );

-- ─────────────────── route_conditions_for_viewer ───────────────────
-- Canonical display read. Mirrors route_markers_for_viewer: caller passes only
-- the route id, the server decides visibility and redaction. Owner gets every
-- report. A non-owner gets every visible report BUT the lat/lng/position_m of
-- any report anchored inside one of the route owner's privacy zones is nulled
-- out (the report itself still shows — "flooded somewhere on this route" — but
-- its location near the owner's home is redacted), so a public course can't
-- leak a pin dropped at the owner's home. Anon callers (auth.uid() null) are
-- non-owner and only reach public routes (raises 42501 otherwise so the surface
-- fails loud).
create or replace function route_conditions_for_viewer(p_route_id uuid)
returns setof route_conditions
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

  -- Owner sees everything, anchors intact.
  if v_caller is not null and v_caller = v_owner then
    return query
      select * from route_conditions
      where route_id = p_route_id
      order by created_at desc;
    return;
  end if;

  -- Non-owner: null out the anchor of any report inside the owner's privacy
  -- zones. The report row still returns; only its coordinates are redacted.
  select prefs->'privacy_zones' into v_zones
    from user_settings where user_id = v_owner;

  return query
    select
      rc.id,
      rc.route_id,
      rc.user_id,
      rc.condition,
      rc.severity,
      rc.note,
      case when rc.lat is not null and rc.lng is not null
                and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
           then null else rc.lat end,
      case when rc.lat is not null and rc.lng is not null
                and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
           then null else rc.lng end,
      case when rc.lat is not null and rc.lng is not null
                and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
           then null else rc.position_m end,
      rc.created_at
    from route_conditions rc
    where rc.route_id = p_route_id
    order by rc.created_at desc;
end;
$$;

revoke execute on function route_conditions_for_viewer(uuid) from public;
grant execute on function route_conditions_for_viewer(uuid) to anon, authenticated, service_role;
