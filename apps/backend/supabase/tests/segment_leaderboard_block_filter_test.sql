-- pgtap suite for the block-aware segment leaderboard (20261115_001).
--
-- segment_leaderboard_tiered must hide efforts by users the caller has
-- blocked, OR who have blocked the caller (is_blocked_either_way), while
-- leaving the caller's own effort and unrelated viewers untouched.
--
-- Reads as authenticated callers via `set local "request.jwt.claims"`.

begin;

select plan(5);

-- ── Fixture: viewer A, other runner B, unrelated viewer C ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000bb0a1', 'authenticated', 'authenticated',
   'viewer-a@block.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000bb0b2', 'authenticated', 'authenticated',
   'other-b@block.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000bb0c3', 'authenticated', 'authenticated',
   'viewer-c@block.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000bb0a1', 'Viewer A'),
  ('00000000-0000-0000-0000-0000000bb0b2', 'Other B'),
  ('00000000-0000-0000-0000-0000000bb0c3', 'Viewer C');

-- A owns a public route + segment.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0a1"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('66666666-6666-6666-6666-6666660bb001',
   '00000000-0000-0000-0000-0000000bb0a1',
   'Block Test Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   10000, true);
insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('77777777-7777-7777-7777-7777770bb001',
   '66666666-6666-6666-6666-6666660bb001',
   'Block Sprint', 500, 1500,
   '00000000-0000-0000-0000-0000000bb0a1');

-- A and B each record a public run + plant one effort on the segment.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-8888880bb001',
   '00000000-0000-0000-0000-0000000bb0a1', now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-7777770bb001',
   '88888888-8888-8888-8888-8888880bb001',
   '00000000-0000-0000-0000-0000000bb0a1', 200, now() - interval '2 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0b2"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-8888880bb002',
   '00000000-0000-0000-0000-0000000bb0b2', now(), 10000, 1900, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-7777770bb001',
   '88888888-8888-8888-8888-8888880bb002',
   '00000000-0000-0000-0000-0000000bb0b2', 250, now() - interval '1 hour');

-- 1. Baseline: viewer A sees both efforts (no block yet).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0a1"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-7777770bb001'::uuid, null, null, 50)),
  2,
  'baseline: viewer sees both runners before any block'
);

-- A blocks B.
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000bb0a1', '00000000-0000-0000-0000-0000000bb0b2');

-- 2. Viewer A now sees only their own effort; B is hidden.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-7777770bb001'::uuid, null, null, 50)),
  1,
  'after A blocks B: blocked runner is hidden from the board'
);
select is(
  (select user_id::text from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-7777770bb001'::uuid, null, null, 50)),
  '00000000-0000-0000-0000-0000000bb0a1',
  'the surviving row is the caller''s own effort'
);

-- 3. An unrelated viewer C still sees both — the block is per-pair.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0c3"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-7777770bb001'::uuid, null, null, 50)),
  2,
  'unrelated viewer is unaffected by the A-B block'
);

-- 4. Reverse direction: B blocks A (A never blocked B). Viewer A must
--    still not see B — is_blocked_either_way is symmetric.
delete from user_blocks
 where blocker_id = '00000000-0000-0000-0000-0000000bb0a1'
   and blocked_id = '00000000-0000-0000-0000-0000000bb0b2';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0b2"}';
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000bb0b2', '00000000-0000-0000-0000-0000000bb0a1');
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb0a1"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-7777770bb001'::uuid, null, null, 50)),
  1,
  'symmetric: a runner who blocked the caller is also hidden'
);

select * from finish();
rollback;
