-- RLS + trigger + viewer-RPC suite for `public.route_markers` (course
-- markers — aid stations / cutoffs / crew access / hazards / climbs).
-- Migrations 20270129_001 + 20270428_001 (viewer contributions).
--
-- Contract under test (post-20270428_001):
--   - "Official" marker  = user_id == route.user_id (dropped by the owner).
--   - "Personal" marker  = user_id != route.user_id (a viewer's own overlay).
--   - INSERT: any authenticated user may add a marker AS THEMSELVES to any
--     route they can SEE (is_route_visible_to). Forging another user_id, or a
--     route the caller can't see, is rejected.
--   - UPDATE/DELETE: your OWN markers only. A viewer can't touch the owner's
--     official markers; the owner can't touch a viewer's personal ones.
--   - SELECT (base policy) + route_markers_for_viewer(): each caller sees THEIR
--     OWN markers plus the owner's OFFICIAL markers (privacy-zone-redacted for
--     non-owners). A viewer's personal markers are private to that viewer —
--     invisible to the owner and to other viewers.
--   - route_markers_set_position() derives position_m along routes.geom.
--
-- Blast radius if regressed: a viewer's personal overlay leaking to the owner
-- or to other viewers; a viewer editing/deleting the owner's official markers
-- (or vice-versa); a forged INSERT; a private route's markers leaking to anon.

begin;

select plan(20);

-- ── Fixture: owner cc001 (with privacy zone), viewer cc002, viewer cc003 ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000cc001', 'authenticated', 'authenticated',
   'route-owner@marker.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc002', 'authenticated', 'authenticated',
   'viewer@marker.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc003', 'authenticated', 'authenticated',
   'viewer3@marker.local', '', now(), now());

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

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';

-- A public and a private route owned by cc001.
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

-- 1. Owner drops an aid station near the END (outside the start privacy zone).
insert into route_markers (id, route_id, user_id, kind, label, lat, lng, meta)
values
  ('33333333-3333-3333-3333-3333000cc001',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   'aid_station', 'Aid 1', 47.38, 8.55,
   '{"services":["water","food"]}');
select pass('owner adds an official marker to their own public route');

-- 2. The position trigger filled position_m from geom.
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

-- 5. Owner sees both public-route official markers via the RPC (no redaction).
select results_eq(
  $$ select count(*)::int from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') $$,
  $$ values (2) $$,
  'owner sees both official public-route markers via the viewer RPC'
);

-- ── Switch to viewer cc002 (non-owner) ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';

-- 6. Non-owner can read the owner's OFFICIAL marker on the public route.
select results_eq(
  $$ select label from route_markers
     where id = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('Aid 1'::text) $$,
  'non-owner can SELECT the owner official marker on a public route'
);

-- 7. Non-owner CANNOT read markers on the PRIVATE route.
select is_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc003' $$,
  'non-owner cannot SELECT a marker on a private route'
);

-- 8. Viewer RPC redacts the in-privacy-zone official marker for a non-owner.
select results_eq(
  $$ select label from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') order by label $$,
  $$ values ('Aid 1'::text) $$,
  'viewer RPC redacts an owner marker inside the owner privacy zone'
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

-- 10. NEW: a non-owner CAN add their OWN personal marker to a public route.
insert into route_markers (id, route_id, user_id, kind, label, lat, lng)
values
  ('33333333-3333-3333-3333-3333000cc010',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc002',
   'note', 'My water stash', 47.375, 8.545);
select pass('non-owner adds their own personal marker to a public route');

-- 11. Viewer sees their personal marker PLUS the owner official one via the RPC.
select results_eq(
  $$ select label from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') order by label $$,
  $$ values ('Aid 1'::text), ('My water stash'::text) $$,
  'viewer sees own personal marker + owner official via the RPC'
);

-- 12. NEW: a non-owner CANNOT add a marker to a route they can't SEE.
select throws_ok(
  $$ insert into route_markers (route_id, user_id, kind, label, lat, lng)
       values ('22222222-2222-2222-2222-2222000cc002',
               '00000000-0000-0000-0000-0000000cc002',
               'note', 'sneaky', 47.38, 8.55) $$,
  '42501',
  null,
  'cannot add a marker to a private route the caller cannot see'
);

-- 13. Non-owner UPDATE on the owner's official marker is a no-op.
update route_markers set label = 'Hacked'
  where id = '33333333-3333-3333-3333-3333000cc001';

-- 14. NEW: a non-owner CAN update their OWN personal marker.
update route_markers set label = 'My water (moved)'
  where id = '33333333-3333-3333-3333-3333000cc010';
select results_eq(
  $$ select label from route_markers
     where id = '33333333-3333-3333-3333-3333000cc010' $$,
  $$ values ('My water (moved)'::text) $$,
  'non-owner can UPDATE their own personal marker'
);

-- 15. kind CHECK rejects an unknown marker kind.
select throws_ok(
  $$ insert into route_markers (route_id, user_id, kind, label, lat, lng)
       values ('22222222-2222-2222-2222-2222000cc001',
               '00000000-0000-0000-0000-0000000cc002',
               'gas_station', 'Bad', 47.38, 8.55) $$,
  '23514',
  null,
  'unknown marker kind is rejected by the CHECK constraint'
);

-- ── Back to the owner cc001 ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';

-- 16. The owner's UPDATE (test 13) was a no-op — Aid 1 is unchanged.
select results_eq(
  $$ select label from route_markers
     where id = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('Aid 1'::text) $$,
  'a non-owner UPDATE on the owner official marker was a no-op'
);

-- 17. NEW: the owner does NOT see the viewer's personal marker via the RPC
--     (they see only their own two official markers).
select results_eq(
  $$ select count(*)::int from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') $$,
  $$ values (2) $$,
  'the owner does not see a viewer personal marker via the RPC'
);

-- 18. NEW: the owner CANNOT delete the viewer's personal marker. The DELETE is
--     an RLS no-op; the owner can't even SELECT a viewer's personal marker, so
--     we confirm it survived from the viewer's own session below (test 19).
delete from route_markers where id = '33333333-3333-3333-3333-3333000cc010';

-- ── Back to viewer cc002 — confirm the owner's delete was a no-op ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
select isnt_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc010' $$,
  'a viewer personal marker survives an owner DELETE attempt (RLS no-op)'
);

-- ── A third viewer cc003 ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc003","role":"authenticated"}';

-- 19. NEW: a third viewer does NOT see cc002's personal marker via the RPC.
select results_eq(
  $$ select label from route_markers_for_viewer(
       '22222222-2222-2222-2222-2222000cc001') order by label $$,
  $$ values ('Aid 1'::text) $$,
  'a third viewer does not see another viewer personal marker via the RPC'
);

-- 20. NEW: a third viewer cannot read cc002's personal marker via direct SELECT.
select is_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc010' $$,
  'a third viewer cannot SELECT another viewer personal marker directly'
);

-- 21. Anon cannot read a marker on a private route.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from route_markers
     where id = '33333333-3333-3333-3333-3333000cc003' $$,
  'anon cannot SELECT a marker on a private route'
);

select * from finish();

rollback;
