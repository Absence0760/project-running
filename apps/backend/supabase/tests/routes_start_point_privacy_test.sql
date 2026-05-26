-- pgtap suite for the privacy-aware routes.start_point trigger
-- (migration 20260925_001 — closes the §33 known v1 gap).
--
-- The trigger reads the route owner's user_settings.prefs.privacy_zones
-- and snaps start_point to the first waypoint NOT inside any zone, or
-- NULL if every waypoint is in a zone. nearby_routes filters
-- `start_point is not null`, so fully-in-zone routes drop out of
-- proximity search entirely — closing the leak where a route built
-- from home would surface in nearby search centred near home.
--
-- A separate trigger on user_settings recomputes start_point for
-- every route the user owns whenever their privacy_zones change.

begin;

select plan(11);

-- ── Fixture: one user with a zone, one user without ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000d201', 'authenticated', 'authenticated',
   'a@startpoint.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000d202', 'authenticated', 'authenticated',
   'b@startpoint.local', '', now(), now());

-- User A has a zone around (47.37, 8.54) with 150 m radius.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000d201',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- User B has no privacy_zones row.

-- ─────────────────────────────────────────────────────────────────────
-- INSERT path — the routes trigger fires before insert.
-- ─────────────────────────────────────────────────────────────────────

-- 1. User without zones → start_point pulled from waypoints[0] (legacy
-- behaviour, unchanged for the no-zones case).
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000d301',
  '00000000-0000-0000-0000-00000000d202',
  'B route — no zones',
  1000,
  '[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55}]'::jsonb,
  true
);

select isnt(
  (select start_point from routes where id = '00000000-0000-0000-0000-00000000d301'),
  null,
  'no-zones user: start_point is populated from waypoints[0]'
);

-- 2. User WITH zone, route that starts IN the zone → start_point snaps
-- forward to the first out-of-zone waypoint (the 0.01° east point ≈ 750 m
-- east, well outside the 150 m radius).
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000d302',
  '00000000-0000-0000-0000-00000000d201',
  'A route — starts in zone',
  1500,
  '[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55},{"lat":47.37,"lng":8.56}]'::jsonb,
  true
);

select cmp_ok(
  st_x((select start_point from routes where id = '00000000-0000-0000-0000-00000000d302')::geometry)::numeric,
  '>', 8.549::numeric,
  'in-zone user: start_point snaps forward to the first out-of-zone waypoint (lng > 8.549)'
);

-- 3. Route ENTIRELY inside the zone → start_point is NULL.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000d303',
  '00000000-0000-0000-0000-00000000d201',
  'A route — entirely in zone',
  100,
  '[{"lat":47.37,"lng":8.5400},{"lat":47.3701,"lng":8.5401},{"lat":47.3702,"lng":8.5402}]'::jsonb,
  true
);

select is(
  (select start_point from routes where id = '00000000-0000-0000-0000-00000000d303'),
  null,
  'fully-in-zone route: start_point is NULL (dropped from nearby search)'
);

-- 4. Empty waypoints → start_point is NULL.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000d304',
  '00000000-0000-0000-0000-00000000d201',
  'A route — empty waypoints',
  0,
  '[]'::jsonb,
  true
);

select is(
  (select start_point from routes where id = '00000000-0000-0000-0000-00000000d304'),
  null,
  'empty waypoints: start_point is NULL'
);

-- 5. nearby_routes hides the in-zone route. Search centred at the zone
-- itself with a generous 1 km radius should find route d302 (which now
-- starts ~750 m east) and NOT find d303 (start_point is NULL).
select is(
  (select count(*) from nearby_routes(47.37, 8.54, 10000.0))::int,
  -- d301 (no-zones user, starts at the same point as the zone) +
  -- d302 (A's snapped point, ~750 m east) + d304 (NULL start_point so
  -- nearby filter excludes it) + d303 (NULL too). d301 starts ≈ at
  -- the search centre; d302 ~750 m east. Both are inside 10 km.
  2::int,
  'nearby_routes returns the 2 routes with non-null start_point '
  '(d303 + d304 are hidden because their start_point is NULL)'
);

-- ─────────────────────────────────────────────────────────────────────
-- UPDATE path — re-saving waypoints re-runs the trigger.
-- ─────────────────────────────────────────────────────────────────────

-- 6. Update A's d303 to add an out-of-zone waypoint at the end —
-- start_point should now snap forward to that point.
update routes
set waypoints = '[{"lat":47.37,"lng":8.5400},{"lat":47.3701,"lng":8.5401},{"lat":47.37,"lng":8.56}]'::jsonb
where id = '00000000-0000-0000-0000-00000000d303';

select isnt(
  (select start_point from routes where id = '00000000-0000-0000-0000-00000000d303'),
  null,
  'after update adds an out-of-zone waypoint: start_point is no longer NULL'
);

-- ─────────────────────────────────────────────────────────────────────
-- user_settings trigger — adding/removing zones recomputes start_point
-- across all of the user's routes.
-- ─────────────────────────────────────────────────────────────────────

-- 7. User B (no zones) currently has d301 with start_point near (47.37, 8.54).
--    Add a privacy zone covering the start — start_point should snap
--    forward.
update user_settings
  set prefs = jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
  where user_id = '00000000-0000-0000-0000-00000000d202';

-- The user_settings UPDATE above was an UPSERT-style replacement —
-- actually it's an UPDATE on the existing row only if one exists. B
-- didn't have a row yet (we never inserted one), so the update is a
-- no-op for B. Insert the row instead.
delete from user_settings where user_id = '00000000-0000-0000-0000-00000000d202';
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000d202',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- Now update prefs to fire the AFTER UPDATE trigger.
update user_settings
  set prefs = jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150),
      jsonb_build_object('lat', 0, 'lng', 0, 'radius_m', 1)
    )
  )
  where user_id = '00000000-0000-0000-0000-00000000d202';

-- d301 had waypoints [(47.37, 8.54), (47.37, 8.55)]. With the zone
-- now covering the first point, start_point should snap to (47.37, 8.55).
select cmp_ok(
  st_x((select start_point from routes where id = '00000000-0000-0000-0000-00000000d301')::geometry)::numeric,
  '>', 8.549::numeric,
  'user_settings trigger: adding a zone snaps d301 forward (lng > 8.549)'
);

-- 8. Remove all zones — start_point should revert to waypoints[0].
update user_settings
  set prefs = jsonb_build_object('privacy_zones', '[]'::jsonb)
  where user_id = '00000000-0000-0000-0000-00000000d202';

select cmp_ok(
  st_x((select start_point from routes where id = '00000000-0000-0000-0000-00000000d301')::geometry)::numeric,
  '<', 8.541::numeric,
  'user_settings trigger: removing zones reverts d301 to waypoints[0] (lng < 8.541)'
);

-- 9. Updating a UNRELATED prefs key (not privacy_zones) must NOT
-- trigger the recompute — the trigger short-circuits when
-- privacy_zones is unchanged.
-- Snapshot the current start_point for d301, change a non-zones key,
-- assert it's still the same (and that the trigger noticed the no-op).
-- This is mostly a guard against the trigger getting expensive on
-- every settings flip.
update user_settings
  set prefs = prefs || jsonb_build_object('preferred_unit', 'mi')
  where user_id = '00000000-0000-0000-0000-00000000d202';

-- (We can't directly observe that the recompute was skipped; what we
-- can do is assert the result is still the no-zones start point.)
select cmp_ok(
  st_x((select start_point from routes where id = '00000000-0000-0000-0000-00000000d301')::geometry)::numeric,
  '<', 8.541::numeric,
  'unit pref change does not affect d301 start_point (zones unchanged)'
);

-- ─────────────────────────────────────────────────────────────────────
-- privacy_aware_start_point helper — not user-facing but exercised here.
-- ─────────────────────────────────────────────────────────────────────

-- 10. Helper with null zones returns waypoints[0] (legacy behaviour).
select isnt(
  privacy_aware_start_point(
    '[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55}]'::jsonb,
    null
  ),
  null,
  'privacy_aware_start_point with null zones returns the first waypoint'
);

-- 11. Helper revokes execute from public / anon / authenticated —
-- callers must go through the triggers (or pg_proc inspection).
-- This guards against a future caller accidentally invoking the
-- helper from client code with attacker-controlled zones.
select isnt(
  has_function_privilege(
    'authenticated',
    'public.privacy_aware_start_point(jsonb, jsonb)',
    'execute'
  ),
  true,
  'privacy_aware_start_point is NOT executable by authenticated callers '
  '(triggers run as definer, no direct client path)'
);

select * from finish();
rollback;
