-- RLS suite for `public.live_run_pings`.
--
-- Real-time location broadcasts during a recording session. Visibility
-- mirrors the run: pings of a private run are owner-only; pings of a
-- public run are readable by anyone via the `is_run_visible_to(run_id,
-- caller)` SECURITY DEFINER helper (20260701_001).
--
-- Blast radius if SELECT regresses: a non-owner could stalk a runner
-- in real time. This test pins the read gate for both private and
-- public runs from authenticated and anon callers, plus the
-- write-gate (auth.uid() = user_id AND owns run_id).

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000aaaa01', 'authenticated', 'authenticated',
   'a@ping.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000aaaa02', 'authenticated', 'authenticated',
   'b@ping.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aaaa01"}';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('22222222-2222-2222-2222-222222222201',
   '00000000-0000-0000-0000-000000aaaa01',
   '2026-04-10 10:00:00+00', 1800, 5000, 'app',
   '{"activity_type":"run"}', false),
  ('22222222-2222-2222-2222-222222222202',
   '00000000-0000-0000-0000-000000aaaa01',
   '2026-04-11 10:00:00+00', 2400, 8000, 'app',
   '{"activity_type":"run"}', true);

insert into live_run_pings (run_id, user_id, lat, lng)
values
  ('22222222-2222-2222-2222-222222222201',
   '00000000-0000-0000-0000-000000aaaa01', 47.37, 8.54),
  ('22222222-2222-2222-2222-222222222202',
   '00000000-0000-0000-0000-000000aaaa01', 47.38, 8.55);

-- 1. Owner can read pings for their own run.
select results_eq(
  $$ select count(*)::int from live_run_pings
     where user_id = '00000000-0000-0000-0000-000000aaaa01' $$,
  $$ values (2) $$,
  'owner can read all pings for their runs'
);

-- 2. Non-owner cannot read pings of a private run.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aaaa02"}';
select is_empty(
  $$ select id from live_run_pings
     where run_id = '22222222-2222-2222-2222-222222222201' $$,
  'non-owner cannot read pings of a private run (real-time stalking guard)'
);

-- 3. Non-owner CAN read pings of a public run (via is_run_visible_to).
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '22222222-2222-2222-2222-222222222202' $$,
  $$ values (1) $$,
  'non-owner can read pings of a public run via is_run_visible_to'
);

-- 4. Forged INSERT rejected: caller must own the run AND set
--    user_id = auth.uid().
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng)
     values ('22222222-2222-2222-2222-222222222202',
             '00000000-0000-0000-0000-000000aaaa01', 0, 0) $$,
  '42501',
  null,
  'cannot INSERT a ping under another user_id even on a public run'
);

-- 5. Forged INSERT against caller's own user_id but a run they don't own.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aaaa02"}';
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng)
     values ('22222222-2222-2222-2222-222222222201',
             '00000000-0000-0000-0000-000000aaaa02', 0, 0) $$,
  '42501',
  null,
  'cannot INSERT a ping into a run the caller does not own'
);

-- 6. Non-owner DELETE on someone else's pings: no-op.
delete from live_run_pings
  where run_id = '22222222-2222-2222-2222-222222222202';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000aaaa01"}';
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '22222222-2222-2222-2222-222222222202' $$,
  $$ values (1) $$,
  'non-owner DELETE on a public-run ping is a no-op'
);

-- ── Anonymous ──
set local role anon;
set local "request.jwt.claims" = '';

-- 7. Anon cannot read private-run pings.
select is_empty(
  $$ select id from live_run_pings
     where run_id = '22222222-2222-2222-2222-222222222201' $$,
  'anon cannot read pings of a private run'
);

-- 8. Anon can read public-run pings.
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '22222222-2222-2222-2222-222222222202' $$,
  $$ values (1) $$,
  'anon can read pings of a public run via is_run_visible_to'
);

select * from finish();

rollback;
