-- RLS backstop for shadow_hidden on user_profiles + routes (migration
-- 20270329_001), completing the clubs + events backstop (20270328_001,
-- decisions §206). A moderation auto-hidden profile must drop out of the
-- base-table SELECT policy and the public_profiles view for every OTHER
-- caller while the owner keeps their own row; a hidden route must drop
-- out of private.is_route_visible_to's public branch (which backs the
-- route-photos bucket, route_photos / route_reviews / segments /
-- route_markers / route_conditions policies) and clip_route_for_viewer,
-- while the owner and active club members keep visibility.
--
-- Companion to rls_shadow_hidden_backstop_test.sql (clubs + events).

begin;

select plan(10);

-- ── Fixture (runs as the test-runner role → bypasses RLS) ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000e0001', 'authenticated', 'authenticated',
   'hidden@hide2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000e0002', 'authenticated', 'authenticated',
   'member@hide2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000e0003', 'authenticated', 'authenticated',
   'stranger@hide2.local', '', now(), now());

insert into user_profiles (id, display_name, shadow_hidden)
values
  ('00000000-0000-0000-0000-0000000e0001', 'Hidden Runner', true),
  ('00000000-0000-0000-0000-0000000e0002', 'Visible Runner', false);

-- A club whose member (e0002) must keep visibility of a hidden club route.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-0000000e0001',
   'Hidden Route Harriers', 'hidden-route-harriers', true);

insert into club_members (club_id, user_id, role, status)
values
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-0000000e0002', 'member', 'active');

-- r..01: public + shadow-hidden, no club — the direct-by-id leak path.
-- r..02: public + shadow-hidden club route — pins the member carve-out.
-- r..03: public, NOT hidden — control.
insert into routes (id, user_id, name, waypoints, distance_m, is_public, club_id, shadow_hidden)
values
  ('99999999-9999-9999-9999-999999990001',
   '00000000-0000-0000-0000-0000000e0001',
   'Hidden Loop', '[{"lat":1.0,"lng":2.0}]', 5000, true, null, true),
  ('99999999-9999-9999-9999-999999990002',
   '00000000-0000-0000-0000-0000000e0001',
   'Hidden Club Loop', '[{"lat":1.0,"lng":2.0}]', 5000, true,
   '77777777-7777-7777-7777-777777770002', true),
  ('99999999-9999-9999-9999-999999990003',
   '00000000-0000-0000-0000-0000000e0001',
   'Visible Loop', '[{"lat":1.0,"lng":2.0}]', 5000, true, null, false);

insert into route_photos (id, route_id, owner_id, storage_path)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01',
   '99999999-9999-9999-9999-999999990001',
   '00000000-0000-0000-0000-0000000e0001',
   '00000000-0000-0000-0000-0000000e0001/photo.jpg');

-- ── authenticated stranger: hidden profile is invisible ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0003","role":"authenticated"}';
select is_empty(
  $$ select display_name from user_profiles
     where id = '00000000-0000-0000-0000-0000000e0001' $$,
  'an authenticated stranger cannot SELECT a shadow-hidden profile from the base table'
);
select is_empty(
  $$ select display_name from public_profiles
     where id = '00000000-0000-0000-0000-0000000e0001' $$,
  'an authenticated stranger cannot SELECT a shadow-hidden profile via public_profiles'
);
select results_eq(
  $$ select display_name from user_profiles
     where id = '00000000-0000-0000-0000-0000000e0002' $$,
  $$ values ('Visible Runner'::text) $$,
  'a non-hidden profile stays readable by authenticated callers (control)'
);

-- ── hidden owner still reads their own row ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}';
select results_eq(
  $$ select display_name from user_profiles
     where id = '00000000-0000-0000-0000-0000000e0001' $$,
  $$ values ('Hidden Runner'::text) $$,
  'a shadow-hidden user still SELECTs their own profile row'
);
reset role;

-- ── anon: hidden route is invisible through the visibility helper ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  private.is_route_visible_to('99999999-9999-9999-9999-999999990001', null),
  false,
  'is_route_visible_to is false for a shadow-hidden public route with no viewer'
);
select is_empty(
  $$ select id from route_photos
     where route_id = '99999999-9999-9999-9999-999999990001' $$,
  'anon cannot SELECT route_photos rows of a shadow-hidden route'
);
select throws_ok(
  $$ select clip_route_for_viewer('99999999-9999-9999-9999-999999990001') $$,
  '42501',
  'route not visible',
  'anon clip_route_for_viewer raises 42501 on a shadow-hidden route'
);
select is(
  private.is_route_visible_to('99999999-9999-9999-9999-999999990003', null),
  true,
  'a non-hidden public route stays visible to anon (control)'
);
reset role;

-- ── owner still reads their hidden route's waypoints ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}';
select is(
  clip_route_for_viewer('99999999-9999-9999-9999-999999990001'),
  '[{"lat":1.0,"lng":2.0}]'::jsonb,
  'the owner still gets unclipped waypoints for their own shadow-hidden route'
);

-- ── active club member keeps visibility of a hidden club route ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0002","role":"authenticated"}';
select is(
  private.is_route_visible_to('99999999-9999-9999-9999-999999990002',
                              '00000000-0000-0000-0000-0000000e0002'),
  true,
  'an active club member still sees a shadow-hidden club route (mirrors the clubs carve-out)'
);

select finish();
rollback;
