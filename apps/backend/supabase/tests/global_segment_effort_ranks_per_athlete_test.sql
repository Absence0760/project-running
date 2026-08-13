-- Pins migration 20270523_001 on the CATALOGUE twin:
-- `global_segment_effort_ranks` ranks against the same population
-- `global_segment_leaderboard` does — one row per athlete.
--
-- The catalogue board was reduced to each athlete's best visible effort in
-- 20270513_001; its rank RPC kept counting raw effort rows. Catalogue efforts
-- are unique per (segment, run), so a runner who repeats their local famous
-- climb weekly accumulates one effort per run and the two surfaces drift
-- further apart with every repetition.
--
--   1. A holds 60 s + 65 s, B holds 70 s → B ranks 2, not 3.
--   2. That rank is B's position on the board, asserted against the board.
--   3. An athlete is not their own competitor.
--   4. One effort per athlete is unchanged.
--   5. A blocked athlete's faster effort stops pushing the caller down,
--      matching the board's block filter.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000eb001', 'authenticated', 'authenticated',
   'repeat-a@granks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eb002', 'authenticated', 'authenticated',
   'oneshot-b@granks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eb003', 'authenticated', 'authenticated',
   'fast-c@granks.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000eb001', 'Repeat A'),
  ('00000000-0000-0000-0000-0000000eb002', 'One-shot B'),
  ('00000000-0000-0000-0000-0000000eb003', 'Fast C');

select tests.confirm_consent();

-- Catalogue segments are admin-curated, so they go in before the role switch.
insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a4a4a4a4-0000-0000-0000-0000000000e1', 'Repeat Famous Climb',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true),
  ('a4a4a4a4-0000-0000-0000-0000000000e2', 'Control Famous Climb',
   '[{"lat":41.0,"lng":-73.0},{"lat":41.002,"lng":-73.0}]', 400, true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eb001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values
  ('b4b4b4b4-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000eb001',
   now() - interval '2 hours', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true),
  ('b4b4b4b4-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000eb001',
   now() - interval '1 hour', 5000, 1200, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('c4c4c4c4-0000-0000-0000-0000000000e1', 'a4a4a4a4-0000-0000-0000-0000000000e1',
   'b4b4b4b4-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000eb001',
   60, now() - interval '2 hours'),
  ('c4c4c4c4-0000-0000-0000-0000000000e2', 'a4a4a4a4-0000-0000-0000-0000000000e1',
   'b4b4b4b4-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000eb001',
   65, now() - interval '1 hour'),
  ('c4c4c4c4-0000-0000-0000-0000000000e3', 'a4a4a4a4-0000-0000-0000-0000000000e2',
   'b4b4b4b4-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000eb001',
   300, now() - interval '2 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eb002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b4b4b4b4-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000eb002',
   now(), 5000, 1300, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('c4c4c4c4-0000-0000-0000-0000000000e4', 'a4a4a4a4-0000-0000-0000-0000000000e1',
   'b4b4b4b4-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000eb002',
   70, now()),
  ('c4c4c4c4-0000-0000-0000-0000000000e5', 'a4a4a4a4-0000-0000-0000-0000000000e2',
   'b4b4b4b4-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000eb002',
   200, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eb003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b4b4b4b4-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000eb003',
   now(), 5000, 1100, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('c4c4c4c4-0000-0000-0000-0000000000e6', 'a4a4a4a4-0000-0000-0000-0000000000e2',
   'b4b4b4b4-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000eb003',
   100, now());

-- ── 1-2. The repeat-effort shape, read as B ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eb002"}';

select is(
  (select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e3'::uuid)
     where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e4'),
  2,
  'a rival''s repeat catalogue effort no longer inflates the chip rank'
);

select is(
  (select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e3'::uuid)
     where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e4'),
  (select count(*)::int + 1
     from global_segment_leaderboard('a4a4a4a4-0000-0000-0000-0000000000e1'::uuid)
     where time_seconds < 70),
  'the chip rank equals the athlete''s position on global_segment_leaderboard'
);

-- ── 3-4. Self-exclusion + the unchanged control, read as A ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eb001"}';

select is(
  (select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e2'::uuid)
     where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e2'),
  1,
  'an athlete is not their own competitor: the slower repeat effort still ranks 1'
);

select results_eq(
  $$ select rank from (
       select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e1'::uuid)
         where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e3'
       union all
       select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e3'::uuid)
         where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e5'
       union all
       select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e4'::uuid)
         where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e6'
     ) r order by rank desc $$,
  $$ values (3), (2), (1) $$,
  'one effort per athlete is unchanged: 300 / 200 / 100 rank 3 / 2 / 1'
);

-- ── 5. The block graph, matching the board ──
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000eb001', '00000000-0000-0000-0000-0000000eb003');

select is(
  (select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e1'::uuid)
     where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e3'),
  2,
  'a blocked athlete''s faster effort no longer pushes the caller down the ranking'
);

select is(
  (select rank from global_segment_effort_ranks('b4b4b4b4-0000-0000-0000-0000000000e1'::uuid)
     where effort_id = 'c4c4c4c4-0000-0000-0000-0000000000e3'),
  (select count(*)::int + 1
     from global_segment_leaderboard('a4a4a4a4-0000-0000-0000-0000000000e2'::uuid)
     where time_seconds < 300),
  'chip and board agree on the blocked-rival population'
);

select * from finish();
rollback;
