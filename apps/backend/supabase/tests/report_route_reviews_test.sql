-- pgtap for reporting route reviews (20270402_001). submit_report must
-- accept target_kind 'route_review', reject reporting your own review
-- (author column is route_reviews.user_id), and 404 a missing target.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000f0001', 'authenticated', 'authenticated',
   'owner@rr.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000f0002', 'authenticated', 'authenticated',
   'viewer@rr.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000f0001', 'Owner'),
  ('00000000-0000-0000-0000-0000000f0002', 'Viewer');

-- Owner owns a public route + leaves a review on it.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('66666666-6666-6666-6666-0000000f0001',
   '00000000-0000-0000-0000-0000000f0001',
   'RR Route', '[]'::jsonb, 5000, true);

insert into route_reviews (id, route_id, user_id, rating, comment)
values ('00000000-0000-0000-0000-0000000fa001',
   '66666666-6666-6666-6666-0000000f0001',
   '00000000-0000-0000-0000-0000000f0001', 4, 'abusive review');

-- ── 1. A viewer can report a route review ────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000f0002"}';
select lives_ok(
  $$ select submit_report('route_review', '00000000-0000-0000-0000-0000000fa001'::uuid, 'harassment', null) $$,
  'a viewer can report a route review'
);

-- ── 2. A route_review report row landed ──────────────────────────
select is(
  (select count(*)::int from reports
     where target_kind = 'route_review'
       and target_id = '00000000-0000-0000-0000-0000000fa001'),
  1,
  'a route_review report row exists'
);

-- ── 3. Review author cannot report their own review (22023) ──────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000f0001"}';
select throws_ok(
  $$ select submit_report('route_review', '00000000-0000-0000-0000-0000000fa001'::uuid, 'spam', null) $$,
  '22023',
  null,
  'a user cannot report their own route review'
);

-- ── 4. Missing route review 404s (02000) ─────────────────────────
select throws_ok(
  $$ select submit_report('route_review', '00000000-0000-0000-0000-0000000fa999'::uuid, 'spam', null) $$,
  '02000',
  null,
  'reporting a missing route review raises no_data (02000)'
);

select * from finish();
rollback;
