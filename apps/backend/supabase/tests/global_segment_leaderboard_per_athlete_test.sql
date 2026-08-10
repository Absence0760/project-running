-- Pins migration 20270513_001: one row per athlete on the CATALOGUE segment
-- leaderboard.
--
-- `global_segment_leaderboard` was written from the pre-#393 template and kept
-- returning every effort row. `global_segment_efforts` is unique per
-- (segment, run), so a runner who repeats their local famous climb accumulates
-- an effort per run and could fill the whole board — pushing genuine unique
-- competitors off it entirely, where no client post-filter can recover them.
--
--   1. The board is deduped: one row per athlete, holding their FASTEST effort.
--   2. p_limit counts distinct athletes, not efforts — a repeat runner cannot
--      squeeze a slower athlete off a limited board.
--   3. The reduction runs INSIDE the visibility filters: a faster effort on a
--      private run does not mask the athlete's slower public one.
--   4. The block filter still composes with the reduction.

begin;

select plan(6);

-- ── Fixture: repeat runner A, one-shot B, blocked C ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000da001', 'authenticated', 'authenticated',
   'repeat-a@gsl.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000db002', 'authenticated', 'authenticated',
   'oneshot-b@gsl.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000dc003', 'authenticated', 'authenticated',
   'blocked-c@gsl.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000da001', 'Repeat A'),
  ('00000000-0000-0000-0000-0000000db002', 'One-shot B'),
  ('00000000-0000-0000-0000-0000000dc003', 'Blocked C');

select tests.confirm_consent();

insert into global_segments (id, name, waypoints, distance_m, is_active)
values ('a3a3a3a3-0000-0000-0000-0000000000d1', 'Repeat Hill',
        '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true);

-- A runs it four times: 60/61/62 public, plus a 55 on a PRIVATE run. B runs it
-- once at 70. C runs it once at 50 but is blocked by A.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000da001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values
  ('b3b3b3b3-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000da001',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b3b3b3b3-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000da001',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b3b3b3b3-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000da001',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b3b3b3b3-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000da001',
   now(), 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, false);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-0000000da001', 60, now() - interval '4 hours'),
  ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d2',
   '00000000-0000-0000-0000-0000000da001', 61, now() - interval '3 hours'),
  ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d3',
   '00000000-0000-0000-0000-0000000da001', 62, now() - interval '2 hours'),
  ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d4',
   '00000000-0000-0000-0000-0000000da001', 55, now() - interval '1 hour');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000db002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b3b3b3b3-0000-0000-0000-0000000000d5', '00000000-0000-0000-0000-0000000db002',
        now(), 5000, 1300, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d5',
        '00000000-0000-0000-0000-0000000db002', 70, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dc003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b3b3b3b3-0000-0000-0000-0000000000d6', '00000000-0000-0000-0000-0000000dc003',
        now(), 5000, 1100, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a3a3a3a3-0000-0000-0000-0000000000d1', 'b3b3b3b3-0000-0000-0000-0000000000d6',
        '00000000-0000-0000-0000-0000000dc003', 50, now());

-- ── Board read as a stranger to the block graph: B (own view) ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000db002"}';

-- 1. Three athletes, three rows — not the six efforts that exist.
select is(
  (select count(*)::int from global_segment_leaderboard(
     'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid)),
  3,
  'the board carries one row per athlete, not one per effort'
);

-- 2. Each athlete appears exactly once, in time order, holding their fastest
--    VISIBLE effort. A''s 55s sits on a private run, so A is on the board at
--    60s — the private effort neither shows nor masks the public one.
select results_eq(
  $$ select user_id::text, time_seconds from global_segment_leaderboard(
       'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000dc003', 50),
       ('00000000-0000-0000-0000-0000000da001', 60),
       ('00000000-0000-0000-0000-0000000db002', 70)
  $$,
  'each athlete appears once with their fastest visible effort, time ascending'
);

-- 3. The reduction happens before the LIMIT, so p_limit counts athletes. This
--    is the headline defect: pre-fix a three-row board was C(50) + A(60) +
--    A(61), and B — a distinct competitor with a legitimate time — was pushed
--    off it by A''s own repeat efforts, unrecoverable by any client filter.
select results_eq(
  $$ select user_id::text from global_segment_leaderboard(
       'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid, null, null, 3) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000dc003'),
       ('00000000-0000-0000-0000-0000000da001'),
       ('00000000-0000-0000-0000-0000000db002')
  $$,
  'p_limit counts distinct athletes — a repeat runner cannot fill the board '
  'and push a slower competitor off it'
);

-- 4. Even at p_limit = 1 the single row is one athlete, and it is the fastest.
select results_eq(
  $$ select user_id::text from global_segment_leaderboard(
       'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid, null, null, 1) $$,
  $$ values ('00000000-0000-0000-0000-0000000dc003') $$,
  'p_limit = 1 returns the single fastest athlete'
);

-- 5. A''s own view: A blocks C, so C leaves the board and A stays at 60s (the
--    reduction still runs inside the block filter).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000da001"}';
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000da001', '00000000-0000-0000-0000-0000000dc003');
select results_eq(
  $$ select user_id::text, time_seconds from global_segment_leaderboard(
       'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000da001', 55),
       ('00000000-0000-0000-0000-0000000db002', 70)
  $$,
  'block filter composes with the reduction; the owner sees their own private '
  'effort as their best'
);

-- 6. Malformed age band still raises 22023 — the rewrite kept the guard.
select throws_ok(
  $$ select * from global_segment_leaderboard(
       'a3a3a3a3-0000-0000-0000-0000000000d1'::uuid, null, 'thirties') $$,
  '22023',
  null,
  'malformed p_age_band still raises 22023'
);

select * from finish();
rollback;
