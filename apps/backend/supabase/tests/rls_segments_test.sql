-- RLS suite for `public.segments`.
--
-- Policy stack (per migrations 20260526_001, 20260703_001):
--   - SELECT "segments readable when route is readable" — gated by
--     `is_route_visible_to(route_id, auth.uid())` (owner / public /
--     active club member).
--   - INSERT "segment authors create on readable routes" — caller is
--     `created_by` AND the route must be visible to them.
--   - UPDATE / DELETE "segment author or route owner …" — segment
--     author OR the route's owner. Route admins via club_members
--     work through the routes RLS, not these policies.
--   - CHECK constraints: name length 1..120, start_distance_m >= 0,
--     end_distance_m > start_distance_m, length >= 100 m.
--
-- Blast radius if regressed: pollution of every public route's
-- segment list with forged-attribution rows (closes the same
-- `auth.uid() = created_by` shape as run_kudos / route_reviews), or
-- a non-author / non-owner overwriting another user's segment
-- bounds (which silently invalidates every `segment_efforts` row
-- attached to it, since the unique key is `(segment_id, run_id)`
-- and existing efforts keep pointing at the renamed segment).

begin;

select plan(10);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000bb0001', 'authenticated', 'authenticated',
   'route-owner@segment.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000bb0002', 'authenticated', 'authenticated',
   'segment-author@segment.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000bb0003', 'authenticated', 'authenticated',
   'stranger@segment.local', '', now(), now());

set local role authenticated;

-- Route owner (bb0001) owns one public + one private route.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0001"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('44444444-4444-4444-4444-444444440001',
   '00000000-0000-0000-0000-000000bb0001',
   'Public Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   10000, true),
  ('44444444-4444-4444-4444-444444440002',
   '00000000-0000-0000-0000-000000bb0001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   10000, false);

-- bb0001 (route owner) plants a segment on their private route so
-- test 3 has something for a stranger to fail-to-see.
insert into segments (id, route_id, name, start_distance_m, end_distance_m, created_by)
values
  ('55555555-5555-5555-5555-555555550001',
   '44444444-4444-4444-4444-444444440002',
   'Private Hill',
   1000, 1500,
   '00000000-0000-0000-0000-000000bb0001');

-- bb0002 (segment author) creates a segment on bb0001's public route.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0002"}';
insert into segments (id, route_id, name, start_distance_m, end_distance_m, created_by)
values
  ('55555555-5555-5555-5555-555555550002',
   '44444444-4444-4444-4444-444444440001',
   'Public Sprint',
   200, 600,
   '00000000-0000-0000-0000-000000bb0002');

-- 1. Author can SELECT their own segment on a public route.
select results_eq(
  $$ select name from segments
     where id = '55555555-5555-5555-5555-555555550002' $$,
  $$ values ('Public Sprint'::text) $$,
  'author can SELECT their own segment on a public route'
);

-- 2. Stranger can SELECT a segment on a public route (route is
--    publicly visible, segment visibility tracks it).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0003"}';
select results_eq(
  $$ select name from segments
     where id = '55555555-5555-5555-5555-555555550002' $$,
  $$ values ('Public Sprint'::text) $$,
  'stranger can SELECT a segment on a public route'
);

-- 3. Stranger cannot SELECT a segment on a private route.
select is_empty(
  $$ select id from segments
     where id = '55555555-5555-5555-5555-555555550001' $$,
  'stranger cannot SELECT a segment on a private route they cannot see'
);

-- 4. Forged created_by INSERT is rejected.
select throws_ok(
  $$ insert into segments (route_id, name, start_distance_m, end_distance_m, created_by)
       values ('44444444-4444-4444-4444-444444440001',
               'Forged', 0, 500,
               '00000000-0000-0000-0000-000000bb0002') $$,
  '42501',
  null,
  'cannot INSERT a segment under another user_id'
);

-- 5. INSERT against an invisible private route is rejected.
select throws_ok(
  $$ insert into segments (route_id, name, start_distance_m, end_distance_m, created_by)
       values ('44444444-4444-4444-4444-444444440002',
               'Planted on private', 0, 500,
               '00000000-0000-0000-0000-000000bb0003') $$,
  '42501',
  null,
  'cannot INSERT a segment on a private route the caller cannot see'
);

-- 6. Author can UPDATE their own segment.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0002"}';
update segments set name = 'Sprint Renamed'
  where id = '55555555-5555-5555-5555-555555550002';
select results_eq(
  $$ select name from segments
     where id = '55555555-5555-5555-5555-555555550002' $$,
  $$ values ('Sprint Renamed'::text) $$,
  'author can UPDATE their own segment'
);

-- 7. Stranger UPDATE is a silent no-op (route owner branch is the
--    only other write path and it's not the stranger).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0003"}';
update segments set name = 'Pwned'
  where id = '55555555-5555-5555-5555-555555550002';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000bb0002"}';
select results_eq(
  $$ select name from segments
     where id = '55555555-5555-5555-5555-555555550002' $$,
  $$ values ('Sprint Renamed'::text) $$,
  'stranger UPDATE on another author segment is a no-op'
);

-- 8. CHECK: segments shorter than 100 m are rejected (decisions §37 —
--    leaderboards on tiny slices are meaningless and a DoS vector).
select throws_ok(
  $$ insert into segments (route_id, name, start_distance_m, end_distance_m, created_by)
       values ('44444444-4444-4444-4444-444444440001',
               'Too short', 0, 50,
               '00000000-0000-0000-0000-000000bb0002') $$,
  '23514',
  null,
  'CHECK rejects segments with length_m < 100'
);

-- ── Anon read paths ──
-- Same regression guard as in rls_route_reviews_test.sql: before
-- 20260819_001 moved `is_route_visible_to` to the `private` schema,
-- every anon SELECT against `segments` SEGV'd the backend because
-- anon had no EXECUTE on the function called from the SELECT
-- predicate. Now that anon has EXECUTE on the qualified function,
-- the predicate evaluates correctly.

-- 9. Anon can SELECT a segment on a public route.
set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select name from segments
     where id = '55555555-5555-5555-5555-555555550002' $$,
  $$ values ('Sprint Renamed'::text) $$,
  'anon can SELECT a segment on a public route'
);

-- 10. Anon cannot SELECT a segment on a private route.
select is_empty(
  $$ select id from segments
     where id = '55555555-5555-5555-5555-555555550001' $$,
  'anon cannot SELECT a segment on a private route'
);

select * from finish();

rollback;
