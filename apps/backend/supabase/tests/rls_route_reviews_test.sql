-- RLS suite for `public.route_reviews`.
--
-- Policy stack (final form per migrations 20260414_001, 20260627_001,
-- 20260703_001):
--   - SELECT "reviews on visible routes are readable" — gated by
--     `is_route_visible_to(route_id, auth.uid())` (own / public /
--     club-member). Anon flows through the same helper.
--   - SELECT "users read their own reviews" — own-row escape hatch
--     so the reviewer keeps visibility if the linked route flips
--     public→private after the fact.
--   - INSERT "users insert reviews on visible routes" — caller must
--     be the row's user_id AND the route must be visible to them.
--   - UPDATE / DELETE — author only.
--   - CHECK rating between 1 and 5; UNIQUE (route_id, user_id).
--
-- Blast radius if regressed: pollution of every route's review list
-- (forged INSERT under another user_id, or INSERT against a private
-- route the reviewer cannot see → spam reviews the route owner
-- cannot clean up), plus cross-user UPDATE/DELETE letting one user
-- rewrite or wipe another user's review.

begin;

select plan(10);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000aa0001', 'authenticated', 'authenticated',
   'route-owner@review.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000aa0002', 'authenticated', 'authenticated',
   'reviewer@review.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0001"}';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('22222222-2222-2222-2222-222222220001',
   '00000000-0000-0000-0000-000000aa0001',
   'Public Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, true),
  ('22222222-2222-2222-2222-222222220002',
   '00000000-0000-0000-0000-000000aa0001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, false);

-- The reviewer leaves one review on the public route.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0002"}';
insert into route_reviews (id, route_id, user_id, rating, comment)
values
  ('33333333-3333-3333-3333-333333330001',
   '22222222-2222-2222-2222-222222220001',
   '00000000-0000-0000-0000-000000aa0002',
   4, 'nice loop');

-- 1. Reviewer can read their own review.
select results_eq(
  $$ select rating::int from route_reviews
     where id = '33333333-3333-3333-3333-333333330001' $$,
  $$ values (4) $$,
  'reviewer can SELECT their own review'
);

-- 2. Route owner (different user) can read the review because the
--    route is public.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0001"}';
select results_eq(
  $$ select rating::int from route_reviews
     where id = '33333333-3333-3333-3333-333333330001' $$,
  $$ values (4) $$,
  'non-author can SELECT a review on a public route'
);

-- 3. Forged INSERT under another user_id is rejected.
select throws_ok(
  $$ insert into route_reviews (route_id, user_id, rating, comment)
       values ('22222222-2222-2222-2222-222222220001',
               '00000000-0000-0000-0000-000000aa0002',
               5, 'spoofed') $$,
  '42501',
  null,
  'cannot INSERT a review under another user_id'
);

-- 4. INSERT against an invisible (private) route is rejected, even
--    when the caller correctly uses their own user_id. Closes
--    20260627_001 + 20260703_001.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0002"}';
select throws_ok(
  $$ insert into route_reviews (route_id, user_id, rating, comment)
       values ('22222222-2222-2222-2222-222222220002',
               '00000000-0000-0000-0000-000000aa0002',
               1, 'planted on private route') $$,
  '42501',
  null,
  'cannot INSERT a review on a private route the caller cannot see'
);

-- 5. Non-author UPDATE is a silent no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0001"}';
update route_reviews set rating = 1, comment = 'pwned'
  where id = '33333333-3333-3333-3333-333333330001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0002"}';
select results_eq(
  $$ select rating::int, comment from route_reviews
     where id = '33333333-3333-3333-3333-333333330001' $$,
  $$ values (4, 'nice loop'::text) $$,
  'non-author UPDATE on a review is a no-op'
);

-- 6. Non-author DELETE is a silent no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0001"}';
delete from route_reviews where id = '33333333-3333-3333-3333-333333330001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0002"}';
select results_eq(
  $$ select count(*)::int from route_reviews
     where id = '33333333-3333-3333-3333-333333330001' $$,
  $$ values (1) $$,
  'non-author DELETE on a review is a no-op'
);

-- 7. CHECK constraint: rating must be 1..5.
select throws_ok(
  $$ insert into route_reviews (route_id, user_id, rating)
       values ('22222222-2222-2222-2222-222222220001',
               '00000000-0000-0000-0000-000000aa0002',
               6) $$,
  '23514',
  null,
  'rating > 5 rejected by CHECK constraint'
);

-- 8. UNIQUE (route_id, user_id): one review per user per route.
select throws_ok(
  $$ insert into route_reviews (route_id, user_id, rating)
       values ('22222222-2222-2222-2222-222222220001',
               '00000000-0000-0000-0000-000000aa0002',
               5) $$,
  '23505',
  null,
  'duplicate (route_id, user_id) rejected by UNIQUE constraint'
);

-- ── Anon read paths ──
-- Migration 20260819_001 moved `is_route_visible_to` to the
-- `private` schema (parallel of 20260812_001 for is_run_visible_to)
-- and granted anon EXECUTE on the qualified function, restoring the
-- anon read paths broken by 20260711_001's revoke. Before the
-- migration these tests SEGV'd the PG 17.6 backend (signal 11) on
-- every `select … from route_reviews` as anon — the missing-grant
-- error path crashed instead of raising 42501. Keep these tests:
-- they're the regression guard if the function move is reverted.

-- 9. Anon can read a review on a public route (route is visible to
--    everyone via private.is_route_visible_to).
set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select rating::int from route_reviews
     where id = '33333333-3333-3333-3333-333333330001' $$,
  $$ values (4) $$,
  'anon can SELECT a review on a public route'
);

-- 10. Anon cannot see reviews on a private route. (We plant such a
--     review via the route owner — who can see their own private
--     route, so they're allowed to review it — then check anon's
--     read returns zero rows.)
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aa0001"}';
insert into route_reviews (id, route_id, user_id, rating, comment)
values
  ('33333333-3333-3333-3333-333333330002',
   '22222222-2222-2222-2222-222222220002',
   '00000000-0000-0000-0000-000000aa0001',
   3, 'self-review on private');
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from route_reviews
     where id = '33333333-3333-3333-3333-333333330002' $$,
  'anon cannot SELECT a review on a private route'
);

select * from finish();

rollback;
