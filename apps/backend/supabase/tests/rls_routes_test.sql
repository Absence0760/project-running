-- RLS suite for `public.routes` and the `public_routes` view.
--
-- Policies (per migrations 20260405_001, 20260520_001 club_owned_routes,
-- 20260703_001 public_routes_view):
--   - "users own their routes" — full CRUD when auth.uid() = user_id
--   - "club members read club routes" — SELECT when route.club_id is
--     non-null and the caller is_club_member()
--   - club admins INSERT / UPDATE / DELETE under their club_id
--   - The legacy "public routes are readable by anyone" SELECT policy
--     was DROPPED in 20260703_001 (decisions §33 wire-leak follow-up).
--     Public visibility now flows through `public_routes` view.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000ee0001', 'authenticated', 'authenticated',
   'a@route.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ee0002', 'authenticated', 'authenticated',
   'b@route.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0001"}';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('11111111-1111-1111-1111-111111111101',
   '00000000-0000-0000-0000-000000ee0001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, false),
  ('11111111-1111-1111-1111-111111111102',
   '00000000-0000-0000-0000-000000ee0001',
   'Shared Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   8000, true);

-- 1. Owner can read both routes.
select results_eq(
  $$ select count(*)::int from routes
     where user_id = '00000000-0000-0000-0000-000000ee0001' $$,
  $$ values (2) $$,
  'owner can read both private + public routes'
);

-- 2. Non-owner direct SELECT on `routes` returns ZERO rows even for
--    is_public=true — the wire-leak SELECT policy was dropped.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
select is_empty(
  $$ select id from routes
     where user_id = '00000000-0000-0000-0000-000000ee0001' $$,
  'non-owner direct SELECT on routes returns zero (wire-leak closed)'
);

-- 3. Forged INSERT under another user_id rejected.
select throws_ok(
  $$ insert into routes (user_id, name, waypoints, distance_m)
     values ('00000000-0000-0000-0000-000000ee0001',
             'Forged', '[{"lat":0,"lng":0},{"lat":0,"lng":0}]', 1000) $$,
  '42501',
  null,
  'cannot INSERT a route under another user_id'
);

-- 4. Non-owner UPDATE: no-op.
update routes set name = 'Pwned'
  where id = '11111111-1111-1111-1111-111111111101';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0001"}';
select results_eq(
  $$ select name from routes where id = '11111111-1111-1111-1111-111111111101' $$,
  $$ values ('Private Loop'::text) $$,
  'non-owner UPDATE on a route is a no-op'
);

-- 5. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
delete from routes where id = '11111111-1111-1111-1111-111111111101';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0001"}';
select results_eq(
  $$ select count(*)::int from routes
     where id = '11111111-1111-1111-1111-111111111101' $$,
  $$ values (1) $$,
  'non-owner DELETE on a route is a no-op'
);

-- ── public_routes view ──
-- 6. Non-owner can read the public route via the view.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
select results_eq(
  $$ select id from public_routes
     where user_id = '00000000-0000-0000-0000-000000ee0001' $$,
  $$ values ('11111111-1111-1111-1111-111111111102'::uuid) $$,
  'non-owner can SELECT public routes via public_routes view'
);

-- 7. Anon direct SELECT: ZERO rows.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from routes
     where user_id = '00000000-0000-0000-0000-000000ee0001' $$,
  'anon cannot SELECT from routes base table'
);

-- 8. Anon SELECT on public_routes: gets the public route.
select results_eq(
  $$ select id from public_routes
     where user_id = '00000000-0000-0000-0000-000000ee0001' $$,
  $$ values ('11111111-1111-1111-1111-111111111102'::uuid) $$,
  'anon can SELECT from public_routes view'
);

select * from finish();

rollback;
