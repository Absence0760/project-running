-- RLS + trigger + viewer-RPC suite for `public.route_markers` (course
-- markers — aid stations / cutoffs / crew access / hazards / climbs).
-- Migration 20270129_001.
--
-- Contract under test:
--   - SELECT "markers readable when route is visible" — gated by
--     private.is_route_visible_to(route_id, auth.uid()) (own / public /
--     club-member). Anon flows through the same helper.
--   - INSERT/UPDATE/DELETE require owning the parent route; INSERT also
--     pins user_id = auth.uid().
--   - route_markers_set_position() derives position_m along routes.geom.
--   - route_markers_for_viewer(route_id) gates visibility AND, for a
--     non-owner, redacts any marker inside one of the owner's privacy
--     zones — the marker analogue of clip_route_for_viewer.
--
-- Blast radius if regressed: a private route's markers leaking to anon /
-- non-members; a forged INSERT planting markers on a route the caller
-- doesn't own; or a public course leaking a pin dropped at the owner's
-- home through the viewer RPC.

begin;

select plan(13);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000cc001', 'authenticated', 'authenticated',
   'route-owner@marker.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc002', 'authenticated', 'authenticated',
   'other@marker.local', '', now(), now());

-- Owner has a ~150 m privacy zone around (47.37, 8.54) — the route start.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000cc001',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';

-- A public and a private route, each a ~1.5 km line so geom (and thus
-- position_m) is well-defined and the two marker points are far apart.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   'Public Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   1500, true),
  ('22222222-2222-2222-2222-2222000cc002',
   '00000000-0000-0000-0000-0000000cc001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   1500, false);

-- 1. Owner drops an aid station near the END of the public route (out of
--    the start-anchored privacy zone).
insert into route_markers (id, route_id, user_id, kind, label, lat, lng, meta)
values
  ('33333333-3333-3333-3333-3333000cc001',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   'aid_station', 'Aid 1', 47.38, 8.55,
   '{"services":["water","food"]}');
select pass('owner adds a marker to their own public route');

-- 2. The position trigger filled position_m (non-null, > 0) from geom.
select cmp_ok(
  (select position_m from route_markers
     where id = '33333333-3333-3333-3333-3333000cc001'),
  '>', 0::numeric,
  'position_m is derived from routes.geom on insert'
);

-- 3. Owner drops a second marker INSIDE the start privacy zone.
insert into route_markers (id, route_id, user_id, kind, label, lat, lng)
values
  ('33333333-3333-3333-3333-3333000cc002',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   'note', 'Home gate', 47.37, 8.54);
select pass('owner adds a marker inside their own privacy zone');

-- 4. Owner adds a marker to the PRIVATE route.
insert into route_markers (id, route_id, user_id, kind, label, lat, lng)
values
  ('33333333-3333-3333-3333-3333000cc003',
   '22222222-2222-2222-2222-2222000cc002',
   '00000000-0000-0000-0000-0000000cc001',
   'cutoff', 'Cutoff A', 47.38, 8.55);
select pass('owner adds a marker to their own private route');

-- 5. Owner sees all THREE via the viewer RPC (no redaction for owner).
select results_eq(
  $$ select count(*)::int from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') $$,
  $$ values (2) $$,
  'owner sees both public-route markers via the viewer RPC'
);

-- ── Switch to a different signed-in user (non-owner) ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';

-- 6. Non-owner can read markers on the PUBLIC route (base SELECT policy).
select results_eq(
  $$ select label from route_markers
     where id = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('Aid 1'::text) $$,
  'non-owner can SELECT a marker on a public route'
);

-- 7. Non-owner CANNOT read markers on the PRIVATE route.
select is_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc003' $$,
  'non-owner cannot SELECT a marker on a private route'
);

-- 8. Viewer RPC redacts the in-privacy-zone marker for a non-owner:
--    only the out-of-zone Aid 1 comes back, not the Home gate note.
select results_eq(
  $$ select label from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') order by label $$,
  $$ values ('Aid 1'::text) $$,
  'viewer RPC redacts a non-owner marker inside the owner privacy zone'
);

-- 9. Forged INSERT under another user_id is rejected.
select throws_ok(
  $$ insert into route_markers (route_id, user_id, kind, label, lat, lng)
       values ('22222222-2222-2222-2222-2222000cc001',
               '00000000-0000-0000-0000-0000000cc001',
               'aid_station', 'Forged', 47.38, 8.55) $$,
  '42501',
  null,
  'cannot INSERT a marker under another user_id'
);

-- 10. INSERT against a route the caller does not own is rejected, even
--     with the caller's own user_id (public route → visibility passes,
--     INSERT policy is stricter).
select throws_ok(
  $$ insert into route_markers (route_id, user_id, kind, label, lat, lng)
       values ('22222222-2222-2222-2222-2222000cc001',
               '00000000-0000-0000-0000-0000000cc002',
               'aid_station', 'NotMine', 47.38, 8.55) $$,
  '42501',
  null,
  'cannot add a marker to a route the caller does not own'
);

-- 11. Non-owner UPDATE on a public-route marker is a no-op.
update route_markers set label = 'Hacked'
  where id = '33333333-3333-3333-3333-3333000cc001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';
select results_eq(
  $$ select label from route_markers
     where id = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('Aid 1'::text) $$,
  'non-owner UPDATE on a marker is a no-op'
);

-- 12. The kind CHECK rejects an unknown marker kind.
select throws_ok(
  $$ insert into route_markers (route_id, user_id, kind, label, lat, lng)
       values ('22222222-2222-2222-2222-2222000cc001',
               '00000000-0000-0000-0000-0000000cc001',
               'gas_station', 'Bad', 47.38, 8.55) $$,
  '23514',
  null,
  'unknown marker kind is rejected by the CHECK constraint'
);

-- 13. Anon cannot read a marker on a private route.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc003' $$,
  'anon cannot SELECT a marker on a private route'
);

select * from finish();

rollback;
