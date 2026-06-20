-- Fix the route_conditions INSERT gate so a non-owner can report on a
-- PUBLIC route — the whole point of a community condition layer.
--
-- 20270212_001 copied the route_reviews insert-gate verbatim:
--   with check (auth.uid() = user_id and exists (
--     select 1 from routes where routes.id = route_conditions.route_id))
-- The intent (per the route_reviews header) was that the `exists` subquery
-- "picks up RLS on routes ... own + public + club-readable". But the base
-- `routes` table has NO public-read SELECT policy — public routes are read
-- through the `public_routes` view + clip_route_for_viewer (decisions §33 /
-- §160), so `routes` RLS exposes only own + club routes. The subquery
-- therefore returns no row for a non-owner reporting on a PUBLIC route, and
-- the INSERT is rejected (42501) — exactly the case the feature exists for.
--
-- Fix: gate the INSERT on private.is_route_visible_to(route_id, auth.uid()),
-- the SAME helper the SELECT policy already uses. It returns true for own /
-- public / club-visible routes and false for an enumerated private route id,
-- so any viewer who can SEE the route can report on it, while a private
-- route a non-member enumerates still 42501s. (route_reviews carries the same
-- latent bug; left untouched here — this migration is scoped to the
-- route_conditions feature.)

drop policy "users report conditions on visible routes" on route_conditions;

create policy "users report conditions on visible routes"
  on route_conditions for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and private.is_route_visible_to(route_conditions.route_id, auth.uid())
  );

-- Also fix route_conditions_for_viewer: the non-owner redaction branch built
-- the redacted columns with bare untyped NULLs in CASE, so position_m resolved
-- to plain `numeric` (no typmod) instead of the table's `numeric(10,2)`. A
-- function declared `returns setof route_conditions` enforces the exact column
-- typmod on `return query`, so the non-owner branch raised
-- "structure of query does not match function result type" at call time —
-- breaking the privacy-redacting read for every non-owner viewer. Cast each
-- redacted column to its exact table type. Full body re-emitted (a bare
-- `create or replace` replaces the whole definition — apps/backend/CLAUDE.md).
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
      (case when rc.lat is not null and rc.lng is not null
                 and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
            then null else rc.lat end)::double precision,
      (case when rc.lat is not null and rc.lng is not null
                 and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
            then null else rc.lng end)::double precision,
      (case when rc.lat is not null and rc.lng is not null
                 and privacy_in_any_zone(rc.lat, rc.lng, v_zones)
            then null else rc.position_m end)::numeric(10, 2),
      rc.created_at
    from route_conditions rc
    where rc.route_id = p_route_id
    order by rc.created_at desc;
end;
$$;

revoke execute on function route_conditions_for_viewer(uuid) from public;
grant execute on function route_conditions_for_viewer(uuid) to anon, authenticated, service_role;
