-- Let a viewer add their OWN course markers to a route they can see (a public
-- or club route), while the route owner's markers stay authoritative and
-- untouchable by anyone else. Before this, route_markers write RLS was
-- owner-only (you could only annotate a route you owned).
--
-- Model (no schema change — `user_id` already records the marker's creator):
--   * "Official" marker  = user_id == route.user_id (dropped by the route owner).
--   * "Personal" marker  = user_id != route.user_id (a viewer's own overlay).
--   * INSERT: any authenticated user may add a marker AS THEMSELVES to any route
--     they can see (is_route_visible_to: own / public / club). They can't forge
--     someone else's user_id.
--   * UPDATE / DELETE: your OWN markers only. A viewer can't touch the owner's
--     official markers; the owner can't touch a viewer's personal ones.
--   * Visibility: a personal marker is PRIVATE to its creator (a personal
--     overlay). Everyone who can see the route sees the owner's official markers
--     (privacy-zone-clipped for non-owners); nobody sees another viewer's
--     personal markers. Enforced both at the base SELECT policy (direct reads)
--     and in the canonical route_markers_for_viewer() display read.
--
-- See docs/features/route_markers.md + decisions ADR (viewer marker contributions).

-- Unqualified postgis (privacy_in_any_zone body) — set search_path per the
-- hosted db-push requirement (all postgis-touching migrations carry this).
set search_path = public, extensions;

-- Route-owner lookup that bypasses `routes` RLS. A plain sub-select on routes
-- inside a policy is itself RLS-gated and can return NULL in a nested context,
-- which would hide the owner's OFFICIAL markers from viewers; a SECURITY
-- DEFINER helper returns the owner reliably. (SECURITY DEFINER + pinned
-- search_path per the function-hardening rules.)
create or replace function private.route_owner_id(p_route_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$ select user_id from routes where id = p_route_id $$;

revoke execute on function private.route_owner_id(uuid) from public;
grant execute on function private.route_owner_id(uuid)
  to anon, authenticated, service_role;

-- ─────────────────────── write policies ───────────────────────

-- SELECT: you can read a marker on a route you can see IF it's your own OR it's
-- the route owner's official marker. Prevents a direct table read leaking
-- another viewer's personal overlay. (Privacy-zone redaction of official
-- markers for non-owners still happens in route_markers_for_viewer().)
drop policy if exists "markers readable when route is visible" on route_markers;
create policy "markers readable to owner and self"
  on route_markers for select
  using (
    private.is_route_visible_to(route_markers.route_id, (select auth.uid()))
    and (
      (select auth.uid()) = route_markers.user_id
      or route_markers.user_id = private.route_owner_id(route_markers.route_id)
    )
  );

-- INSERT: add a marker AS YOURSELF to any route you can see.
drop policy if exists "route owner adds markers" on route_markers;
create policy "viewer adds own markers to a visible route"
  on route_markers for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and private.is_route_visible_to(route_markers.route_id, (select auth.uid()))
  );

-- UPDATE: your own markers only (official or personal).
drop policy if exists "route owner updates markers" on route_markers;
create policy "author updates own markers"
  on route_markers for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- DELETE: your own markers only.
drop policy if exists "route owner deletes markers" on route_markers;
create policy "author deletes own markers"
  on route_markers for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- ─────────────────── route_markers_for_viewer (full body) ───────────────────
-- Canonical display read. Each caller sees THEIR OWN markers plus the route
-- owner's OFFICIAL markers (a pin inside the owner's privacy zone is redacted
-- for non-owner viewers). A viewer's personal markers never surface to the
-- route owner or to other viewers. Full body re-emitted per the "bare-body
-- create or replace strips prior fixes" rule — this supersedes 20270129_001's.
create or replace function route_markers_for_viewer(p_route_id uuid)
returns setof route_markers
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_caller uuid := (select auth.uid());
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

  select prefs->'privacy_zones' into v_zones
    from user_settings where user_id = v_owner;

  return query
    select * from route_markers
    where route_id = p_route_id
      and (
        -- The caller's own markers — always visible to them (official when
        -- they own the route, otherwise their personal overlay).
        (v_caller is not null and user_id = v_caller)
        -- The route owner's official markers — visible to everyone who can see
        -- the route; a pin in one of the owner's privacy zones is redacted for
        -- non-owner viewers (the owner reaches their own via the branch above).
        or (
          user_id = v_owner
          and (v_caller = v_owner or not privacy_in_any_zone(lat, lng, v_zones))
        )
      )
    order by position_m nulls last, created_at;
end;
$$;

revoke execute on function route_markers_for_viewer(uuid) from public;
grant execute on function route_markers_for_viewer(uuid) to anon, authenticated, service_role;
