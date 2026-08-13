-- Pins migration 20270523_001: `segment_effort_ranks` ranks against the same
-- population `segment_leaderboard_tiered` does — one row per athlete.
--
-- The boards were reduced to each athlete's best visible effort in
-- 20270424000003 (issue #393); the rank RPC feeding the run-detail chips kept
-- counting raw effort rows, so one athlete could be shown two different ranks
-- for one segment — #2 on the board the chip links to, #3 on the chip.
--
--   1. The triage shape: A holds 60 s + 65 s, B holds 70 s → B ranks 2, not 3.
--   2. That rank is the athlete's position on the board, asserted against the
--      board itself rather than against a hand-computed number.
--   3. An athlete never competes with themselves — A's slower 65 s effort does
--      not count A's own 60 s above it.
--   4. One effort per athlete is the unchanged case: identical ranks pre/post.
--   5. RLS still bounds the population: an effort on a private run is counted
--      by nobody but its owner.
--   6. The block graph now bounds it too, matching the board: a blocked
--      athlete's faster effort stops pushing the caller down the ranking.

begin;

select plan(8);

-- ── Fixture: repeat runner A, one-shot B, fast C, private-run D ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ea001', 'authenticated', 'authenticated',
   'repeat-a@ranks2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ea002', 'authenticated', 'authenticated',
   'oneshot-b@ranks2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ea003', 'authenticated', 'authenticated',
   'fast-c@ranks2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ea004', 'authenticated', 'authenticated',
   'private-d@ranks2.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000ea001', 'Repeat A'),
  ('00000000-0000-0000-0000-0000000ea002', 'One-shot B'),
  ('00000000-0000-0000-0000-0000000ea003', 'Fast C'),
  ('00000000-0000-0000-0000-0000000ea004', 'Private D');

select tests.confirm_consent();

-- A owns a public route carrying three segments: S1 is the repeat-effort
-- shape, S2 the one-effort-per-athlete control, S3 the visibility case.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea001"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('66666666-6666-6666-6666-66666666ea01',
   '00000000-0000-0000-0000-0000000ea001', 'Per-Athlete Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, true);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('77777777-7777-7777-7777-77777777ea01',
   '66666666-6666-6666-6666-66666666ea01', 'Repeat Climb', 500, 1500,
   '00000000-0000-0000-0000-0000000ea001'),
  ('77777777-7777-7777-7777-77777777ea02',
   '66666666-6666-6666-6666-66666666ea01', 'Control Climb', 2000, 3000,
   '00000000-0000-0000-0000-0000000ea001'),
  ('77777777-7777-7777-7777-77777777ea03',
   '66666666-6666-6666-6666-66666666ea01', 'Visibility Climb', 4000, 5000,
   '00000000-0000-0000-0000-0000000ea001');

-- A: three public runs. RUN1 carries S1@60 + S2@300, RUN2 the repeat S1@65,
-- RUN3 the S3@60 the visibility assertions read.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values
  ('88888888-8888-8888-8888-88888888ea01', '00000000-0000-0000-0000-0000000ea001',
   now() - interval '3 hours', 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('88888888-8888-8888-8888-88888888ea02', '00000000-0000-0000-0000-0000000ea001',
   now() - interval '2 hours', 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('88888888-8888-8888-8888-88888888ea03', '00000000-0000-0000-0000-0000000ea001',
   now() - interval '1 hour', 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ea11', '77777777-7777-7777-7777-77777777ea01',
   '88888888-8888-8888-8888-88888888ea01', '00000000-0000-0000-0000-0000000ea001',
   60, now() - interval '3 hours'),
  ('99999999-9999-9999-9999-99999999ea12', '77777777-7777-7777-7777-77777777ea01',
   '88888888-8888-8888-8888-88888888ea02', '00000000-0000-0000-0000-0000000ea001',
   65, now() - interval '2 hours'),
  ('99999999-9999-9999-9999-99999999ea21', '77777777-7777-7777-7777-77777777ea02',
   '88888888-8888-8888-8888-88888888ea01', '00000000-0000-0000-0000-0000000ea001',
   300, now() - interval '3 hours'),
  ('99999999-9999-9999-9999-99999999ea31', '77777777-7777-7777-7777-77777777ea03',
   '88888888-8888-8888-8888-88888888ea03', '00000000-0000-0000-0000-0000000ea001',
   60, now() - interval '1 hour');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ea04', '00000000-0000-0000-0000-0000000ea002',
   now(), 10000, 1900, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ea13', '77777777-7777-7777-7777-77777777ea01',
   '88888888-8888-8888-8888-88888888ea04', '00000000-0000-0000-0000-0000000ea002',
   70, now()),
  ('99999999-9999-9999-9999-99999999ea22', '77777777-7777-7777-7777-77777777ea02',
   '88888888-8888-8888-8888-88888888ea04', '00000000-0000-0000-0000-0000000ea002',
   200, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ea05', '00000000-0000-0000-0000-0000000ea003',
   now(), 10000, 1700, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ea23', '77777777-7777-7777-7777-77777777ea02',
   '88888888-8888-8888-8888-88888888ea05', '00000000-0000-0000-0000-0000000ea003',
   100, now()),
  ('99999999-9999-9999-9999-99999999ea32', '77777777-7777-7777-7777-77777777ea03',
   '88888888-8888-8888-8888-88888888ea05', '00000000-0000-0000-0000-0000000ea003',
   50, now());

-- D's 55 s on S3 sits on a PRIVATE run — faster than A's 60 s, invisible to
-- everyone but D.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea004"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ea06', '00000000-0000-0000-0000-0000000ea004',
   now(), 10000, 1600, 'app', '{"activity_type":"run"}'::jsonb, false);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ea33', '77777777-7777-7777-7777-77777777ea03',
   '88888888-8888-8888-8888-88888888ea06', '00000000-0000-0000-0000-0000000ea004',
   55, now());

-- ── 1-2. The triage shape, read as B ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea002"}';

-- A holds 60 + 65, B holds 70. Pre-fix the raw effort count made this 3.
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea04'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea13'),
  2,
  'a rival''s repeat effort no longer inflates the chip rank (60 + 65 vs 70 → 2)'
);

-- The number is only right if it is the board's number. Rank on a per-athlete
-- board = 1 + the athletes ahead, which is what the client's
-- assignCompetitionRanks assigns to B's row.
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea04'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea13'),
  (select count(*)::int + 1
     from segment_leaderboard_tiered('77777777-7777-7777-7777-77777777ea01'::uuid)
     where time_seconds < 70),
  'the chip rank equals the athlete''s position on segment_leaderboard_tiered'
);

-- ── 3-4. Self-exclusion + the unchanged control, read as A ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ea001"}';

select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea01'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea11'),
  1,
  'the fastest athlete still ranks 1'
);

-- A's slower repeat effort must not count A's own faster one above it — that
-- would put A at #2, a rank the board gives to B.
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea02'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea12'),
  1,
  'an athlete is not their own competitor: the slower repeat effort still ranks 1'
);

-- One effort per athlete: C@100 / B@200 / A@300 rank 1 / 2 / 3 exactly as they
-- did before the reduction — the change is a no-op on the common shape.
select results_eq(
  $$ select rank from (
       select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea01'::uuid)
         where effort_id = '99999999-9999-9999-9999-99999999ea21'
       union all
       select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea04'::uuid)
         where effort_id = '99999999-9999-9999-9999-99999999ea22'
       union all
       select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea05'::uuid)
         where effort_id = '99999999-9999-9999-9999-99999999ea23'
     ) r order by rank desc $$,
  $$ values (3), (2), (1) $$,
  'one effort per athlete is unchanged: 300 / 200 / 100 rank 3 / 2 / 1'
);

-- ── 5. RLS still bounds the population ──
-- D's faster 55 s is on a private run, so A sees only C ahead of them.
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea03'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea31'),
  2,
  'an effort on a private run is invisible to the ranking'
);

-- ── 6. The block graph bounds it too, matching the board ──
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000ea001', '00000000-0000-0000-0000-0000000ea003');

select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea03'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea31'),
  1,
  'a blocked athlete''s faster effort no longer pushes the caller down the ranking'
);

select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ea03'::uuid)
     where effort_id = '99999999-9999-9999-9999-99999999ea31'),
  (select count(*)::int + 1
     from segment_leaderboard_tiered('77777777-7777-7777-7777-77777777ea03'::uuid)
     where time_seconds < 60),
  'chip and board agree on the blocked-rival population'
);

select * from finish();
rollback;
