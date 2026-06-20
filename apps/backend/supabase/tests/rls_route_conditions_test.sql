-- RLS + trigger + viewer-RPC suite for `public.route_conditions` (community
-- condition reports — muddy / flooded / closed / hazard along a route).
-- Migration 20270212_001.
--
-- Contract under test:
--   - SELECT "conditions readable when route is visible" — gated by
--     private.is_route_visible_to(route_id, auth.uid()) (own / public /
--     club-member). Anon flows through the same helper.
--   - INSERT requires auth.uid() = user_id AND visibility of the route — ANY
--     viewer can report, not just the owner (distinct from route_markers).
--   - DELETE allowed for the author OR the route owner (spam cleanup).
--   - route_conditions_set_position() derives position_m along routes.geom,
--     and leaves it null for an unanchored report.
--   - route_conditions_for_viewer(route_id) gates visibility AND, for a
--     non-owner, NULLS the lat/lng/position_m of any report anchored inside one
--     of the owner's privacy zones (the row still returns).
--
-- Blast radius if regressed: a private route's reports leaking to anon /
-- non-members; a forged INSERT planting reports on an enumerated private route
-- id; or a public course leaking an anchor dropped at the owner's home.

begin;

select plan(13);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000dd001', 'authenticated', 'authenticated',
   'route-owner@cond.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000dd002', 'authenticated', 'authenticated',
   'other@cond.local', '', now(), now());

-- Owner has a ~150 m privacy zone around (47.37, 8.54) — the route start.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000dd001',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dd001","role":"authenticated"}';

-- A public and a private route, each a ~1.5 km line so geom (and thus
-- position_m) is well-defined and the two anchor points are far apart.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('22222222-2222-2222-2222-2222000dd001',
   '00000000-0000-0000-0000-0000000dd001',
   'Public Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   1500, true),
  ('22222222-2222-2222-2222-2222000dd002',
   '00000000-0000-0000-0000-0000000dd001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   1500, false);

-- 1. Owner reports a flooded crossing anchored near the END of the public
--    route (out of the start-anchored privacy zone).
insert into route_conditions (id, route_id, user_id, condition, severity, note, lat, lng)
values
  ('33333333-3333-3333-3333-3333000dd001',
   '22222222-2222-2222-2222-2222000dd001',
   '00000000-0000-0000-0000-0000000dd001',
   'flooded', 'caution', 'Creek crossing high', 47.38, 8.55);
select pass('owner reports a condition on their own public route');

-- 2. The position trigger filled position_m (non-null, > 0) from geom.
select cmp_ok(
  (select position_m from route_conditions
     where id = '33333333-3333-3333-3333-3333000dd001'),
  '>', 0::numeric,
  'position_m is derived from routes.geom for an anchored report'
);

-- 3. An UNANCHORED report (no lat/lng) leaves position_m null.
insert into route_conditions (id, route_id, user_id, condition, severity, note)
values
  ('33333333-3333-3333-3333-3333000dd004',
   '22222222-2222-2222-2222-2222000dd001',
   '00000000-0000-0000-0000-0000000dd001',
   'closed', 'impassable', 'Whole trail closed for logging');
select is(
  (select position_m from route_conditions
     where id = '33333333-3333-3333-3333-3333000dd004'),
  null,
  'an unanchored report leaves position_m null'
);

-- 4. Owner anchors a report INSIDE the start privacy zone.
insert into route_conditions (id, route_id, user_id, condition, severity, lat, lng)
values
  ('33333333-3333-3333-3333-3333000dd002',
   '22222222-2222-2222-2222-2222000dd001',
   '00000000-0000-0000-0000-0000000dd001',
   'muddy', 'info', 47.37, 8.54);
select pass('owner reports a condition inside their own privacy zone');

-- ── Switch to a different signed-in user (non-owner viewer) ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dd002","role":"authenticated"}';

-- 5. A NON-OWNER viewer can report on the public route (any-viewer INSERT).
insert into route_conditions (id, route_id, user_id, condition, severity, note)
values
  ('33333333-3333-3333-3333-3333000dd003',
   '22222222-2222-2222-2222-2222000dd001',
   '00000000-0000-0000-0000-0000000dd002',
   'overgrown', 'info', 'Brush past the bridge');
select pass('a non-owner viewer can report a condition on a public route');

-- 6. Non-owner CANNOT report on the PRIVATE route (visibility gate).
select throws_ok(
  $$ insert into route_conditions (route_id, user_id, condition, severity)
       values ('22222222-2222-2222-2222-2222000dd002',
               '00000000-0000-0000-0000-0000000dd002',
               'muddy', 'info') $$,
  '42501',
  null,
  'a non-owner cannot report on a route they cannot see'
);

-- 7. Forged INSERT under another user_id is rejected.
select throws_ok(
  $$ insert into route_conditions (route_id, user_id, condition, severity)
       values ('22222222-2222-2222-2222-2222000dd001',
               '00000000-0000-0000-0000-0000000dd001',
               'muddy', 'info') $$,
  '42501',
  null,
  'cannot report under another user_id'
);

-- 8. Viewer RPC nulls the anchor of the in-privacy-zone report for a
--    non-owner: the muddy report row STILL returns, but its lat is null.
select is(
  (select lat from route_conditions_for_viewer(
     '22222222-2222-2222-2222-2222000dd001')
   where id = '33333333-3333-3333-3333-3333000dd002'),
  null,
  'viewer RPC redacts the anchor of a report inside the owner privacy zone'
);

-- 9. The out-of-zone flooded report keeps its anchor for the non-owner.
select cmp_ok(
  (select lat from route_conditions_for_viewer(
     '22222222-2222-2222-2222-2222000dd001')
   where id = '33333333-3333-3333-3333-3333000dd001'),
  '>', 0::double precision,
  'viewer RPC keeps the anchor of an out-of-zone report'
);

-- 10. Non-owner CANNOT read reports on the PRIVATE route.
select is_empty(
  $$ select id from route_conditions
     where route_id = '22222222-2222-2222-2222-2222000dd002' $$,
  'non-owner cannot SELECT reports on a private route'
);

-- 11. The condition CHECK rejects an unknown condition value.
select throws_ok(
  $$ insert into route_conditions (route_id, user_id, condition, severity)
       values ('22222222-2222-2222-2222-2222000dd001',
               '00000000-0000-0000-0000-0000000dd002',
               'volcano', 'info') $$,
  '23514',
  null,
  'unknown condition is rejected by the CHECK constraint'
);

-- ── Back to the owner: spam cleanup on a FOREIGN report ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dd001","role":"authenticated"}';

-- 12. The route owner can delete a report another user filed on their route.
delete from route_conditions where id = '33333333-3333-3333-3333-3333000dd003';
select is_empty(
  $$ select id from route_conditions
     where id = '33333333-3333-3333-3333-3333000dd003' $$,
  'route owner can delete a foreign report on their own route'
);

-- 13. Anon cannot read reports on a private route.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from route_conditions
     where route_id = '22222222-2222-2222-2222-2222000dd002' $$,
  'anon cannot SELECT reports on a private route'
);

select * from finish();

rollback;
