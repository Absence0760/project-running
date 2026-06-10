-- pgtap suite for `segment_effort_ranks` (migration 20261223_001).
--
-- The RPC replaces a client-side N+1 count-per-effort loop in
-- fetchEffortsForRun(): given a run id it returns one (effort_id, rank)
-- row per segment effort attached to the run, where rank = 1 + the number
-- of strictly-faster efforts on the SAME segment that are visible to the
-- caller (SECURITY INVOKER → segment_efforts RLS). Tie semantics match the
-- prior `count(strictly-faster) + 1`: tied fastest times share rank 1, the
-- next ranks 3 (standard competition ranking).
--
-- Covers:
--   1. A run with efforts on two segments gets both ranks in one call,
--      each ranked only against its own segment.
--   2. The fastest effort on a segment ranks 1.
--   3. Tied fastest times both rank 1 (strictly-faster count, not row count).
--   4. The slowest effort ranks last (= total efforts on the segment).
--   5. A run with no efforts returns zero rows (not an error).

begin;

select plan(5);

-- ── Fixture: one owner + three other athletes on a public route ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ce001', 'authenticated', 'authenticated',
   'owner@ranks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ce002', 'authenticated', 'authenticated',
   'a2@ranks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ce003', 'authenticated', 'authenticated',
   'a3@ranks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ce004', 'authenticated', 'authenticated',
   'a4@ranks.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000ce001', 'Owner'),
  ('00000000-0000-0000-0000-0000000ce002', 'Athlete 2'),
  ('00000000-0000-0000-0000-0000000ce003', 'Athlete 3'),
  ('00000000-0000-0000-0000-0000000ce004', 'Athlete 4');

-- Owner creates a public route with two segments.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce001"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('66666666-6666-6666-6666-66666666ce01',
   '00000000-0000-0000-0000-0000000ce001', 'Ranks Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, true);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('77777777-7777-7777-7777-77777777ce01',
   '66666666-6666-6666-6666-66666666ce01', 'Segment One', 500, 1500,
   '00000000-0000-0000-0000-0000000ce001'),
  ('77777777-7777-7777-7777-77777777ce02',
   '66666666-6666-6666-6666-66666666ce01', 'Segment Two', 2000, 3000,
   '00000000-0000-0000-0000-0000000ce001');

-- Each athlete records a run + plants efforts (runs + segment_efforts insert
-- RLS both require auth.uid() = user_id, so switch the JWT per owner).
-- S1 times: RUN1=250, RUN2=200, RUN3=200 (tie), RUN4=300.
-- S2 times: RUN1=100, RUN2=120, RUN4=90.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ce01',
   '00000000-0000-0000-0000-0000000ce001', now(), 10000, 1800, 'app',
   '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ce11',
   '77777777-7777-7777-7777-77777777ce01', '88888888-8888-8888-8888-88888888ce01',
   '00000000-0000-0000-0000-0000000ce001', 250, now()),
  ('99999999-9999-9999-9999-99999999ce12',
   '77777777-7777-7777-7777-77777777ce02', '88888888-8888-8888-8888-88888888ce01',
   '00000000-0000-0000-0000-0000000ce001', 100, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ce02',
   '00000000-0000-0000-0000-0000000ce002', now(), 10000, 1800, 'app',
   '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ce21',
   '77777777-7777-7777-7777-77777777ce01', '88888888-8888-8888-8888-88888888ce02',
   '00000000-0000-0000-0000-0000000ce002', 200, now()),
  ('99999999-9999-9999-9999-99999999ce22',
   '77777777-7777-7777-7777-77777777ce02', '88888888-8888-8888-8888-88888888ce02',
   '00000000-0000-0000-0000-0000000ce002', 120, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ce03',
   '00000000-0000-0000-0000-0000000ce003', now(), 10000, 1800, 'app',
   '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ce31',
   '77777777-7777-7777-7777-77777777ce01', '88888888-8888-8888-8888-88888888ce03',
   '00000000-0000-0000-0000-0000000ce003', 200, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce004"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ce04',
   '00000000-0000-0000-0000-0000000ce004', now(), 10000, 1800, 'app',
   '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999ce41',
   '77777777-7777-7777-7777-77777777ce01', '88888888-8888-8888-8888-88888888ce04',
   '00000000-0000-0000-0000-0000000ce004', 300, now()),
  ('99999999-9999-9999-9999-99999999ce42',
   '77777777-7777-7777-7777-77777777ce02', '88888888-8888-8888-8888-88888888ce04',
   '00000000-0000-0000-0000-0000000ce004', 90, now());

-- ── Assertions (read as the owner; the route is public so all efforts
--    are visible to every caller — ranks are global per segment). ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ce001"}';

-- 1. RUN1 has two efforts. S1@250 is 3rd (two 200s ahead); S2@100 is 2nd
--    (one 90 ahead). One call returns both, each ranked within its segment.
select results_eq(
  $$ select effort_id::text, rank
       from segment_effort_ranks('88888888-8888-8888-8888-88888888ce01'::uuid)
       order by rank $$,
  $$ values
       ('99999999-9999-9999-9999-99999999ce12', 2),
       ('99999999-9999-9999-9999-99999999ce11', 3) $$,
  'multi-segment run is ranked per-segment in a single call'
);

-- 2. RUN2's S1@200 is the (tied) fastest → rank 1; its S2@120 is 3rd.
select results_eq(
  $$ select rank
       from segment_effort_ranks('88888888-8888-8888-8888-88888888ce02'::uuid)
       order by rank $$,
  $$ values (1), (3) $$,
  'fastest effort ranks 1; slower effort ranks by strictly-faster count'
);

-- 3. RUN3's S1@200 ties RUN2's S1@200 — both rank 1 (no strictly-faster).
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888ce03'::uuid)),
  1,
  'tied fastest times both rank 1 (strictly-faster count, not row count)'
);

-- 4. RUN4's S1@300 is slowest of four → rank 4; its S2@90 is fastest → 1.
select results_eq(
  $$ select rank
       from segment_effort_ranks('88888888-8888-8888-8888-88888888ce04'::uuid)
       order by rank $$,
  $$ values (1), (4) $$,
  'slowest effort ranks last (= total efforts on its segment)'
);

-- 5. A run with no efforts returns zero rows, not an error.
select is(
  (select count(*)::int
     from segment_effort_ranks('88888888-8888-8888-8888-88888888ceff'::uuid)),
  0,
  'a run with no segment efforts returns zero rows'
);

select * from finish();
rollback;
