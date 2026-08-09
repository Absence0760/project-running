-- pgtap suite for `gym_workout_summaries` + `gym_has_weighted_sets`
-- (migration 20270515_001).
--
-- The SQL half of the drift pin. `apps/web/src/lib/gym/gym_workout_summaries.
-- test.ts` builds the SAME fixture and asserts the SAME expected answer by
-- running the real gym_prs.ts RunningPrTracker; this file asserts it by calling
-- the RPC. Change the PR definition on one side and the other fails.
--
-- Fixture (oldest -> newest), chosen to separate the three PR metrics:
--   w1  Bench 60x5, Bench 60x8, OHP 40x8, Pull-up 10xnull   first of everything
--   w2  Bench 60x5, " " 5x50                                beats nothing
--   w3  "bench  press" 62.5x3                               weight PR only
--   w4  Pull-up 12xnull                                     bodyweight, no PR
--   w5  Back Squat 100x5                                    new exercise
--   w6  OHP 40x10                                           volume + e1rm PR
--
-- Covers:
--   * is_pr true for exactly w1, w3, w5, w6
--   * a weight PR judged across a whitespace-collapsed name (w3 vs w1)
--   * a volume + e1rm PR at an unchanged top weight (w6 vs w1)
--   * the PR judgement running over ALL history, not just the returned page
--   * exercise_count excluding a whitespace-only name, while the trigger-
--     maintained set_count / volume_kg still count that set's work
--   * newest-first ordering
--   * gym_has_weighted_sets all-time, and false for a bodyweight-only lifter
--   * owner-scoping (a stranger sees none of this user's workouts)

begin;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000d0001'::uuid, 'authenticated', 'authenticated',
   'lifter@summaries.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000d0002'::uuid, 'authenticated', 'authenticated',
   'bodyweight@summaries.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000d0099'::uuid, 'authenticated', 'authenticated',
   'stranger@summaries.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000d0001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000d0002', 'Bodyweight'),
  ('00000000-0000-0000-0000-0000000d0099', 'Stranger');

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01',
   '00000000-0000-0000-0000-0000000d0001', 'w1', now() - interval '6 days'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02',
   '00000000-0000-0000-0000-0000000d0001', 'w2', now() - interval '5 days'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd03',
   '00000000-0000-0000-0000-0000000d0001', 'w3', now() - interval '4 days'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd04',
   '00000000-0000-0000-0000-0000000d0001', 'w4', now() - interval '3 days'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd05',
   '00000000-0000-0000-0000-0000000d0001', 'w5', now() - interval '2 days'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd06',
   '00000000-0000-0000-0000-0000000d0001', 'w6', now() - interval '1 day');

insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 0, 'Bench Press', 5, 60),
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 1, 'Bench Press', 8, 60),
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 2, 'Overhead Press', 8, 40),
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 3, 'Pull-up', 10, null),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02', 0, 'Bench Press', 5, 60),
  -- A whitespace-only name passes the length(1..120) CHECK.
  ('dddddddd-dddd-dddd-dddd-dddddddddd02', 1, ' ', 5, 50),
  ('dddddddd-dddd-dddd-dddd-dddddddddd03', 0, 'bench  press', 3, 62.5),
  ('dddddddd-dddd-dddd-dddd-dddddddddd04', 0, 'Pull-up', 12, null),
  ('dddddddd-dddd-dddd-dddd-dddddddddd05', 0, 'Back Squat', 5, 100),
  ('dddddddd-dddd-dddd-dddd-dddddddddd06', 0, 'Overhead Press', 10, 40);

-- 1. Exactly four of the six workouts set a PR.
select is(
  (select array_agg(title order by title)
     from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id
    where s.is_pr),
  array['w1', 'w3', 'w5', 'w6'],
  'is_pr is true for exactly the four workouts RunningPrTracker flags'
);

-- 2. w2 repeats a lighter bench and adds a blank-named set — nothing new.
select is(
  (select is_pr from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w2'),
  false,
  'a workout that beats no prior best is not a PR'
);

-- 3. "bench  press" 62.5 kg is judged against "Bench Press" 60 kg — one
--    exercise once the name is normalised, so this is a weight PR.
select is(
  (select is_pr from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w3'),
  true,
  'a heavier set under a whitespace-differing spelling is still a weight PR'
);

-- 4. w6 repeats 40 kg but for 10 reps: volume 400 > 320 and e1rm 53.3 > 50.7.
select is(
  (select is_pr from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w6'),
  true,
  'more reps at an unchanged weight is a volume + e1rm PR'
);

-- 5. p_limit bounds the rows returned, not the history judged: w2 is still
--    suppressed by w1, which the limit excludes from the result set.
select is(
  (select count(*)::int from gym_workout_summaries(5)),
  5,
  'p_limit bounds the returned rows'
);
select is(
  (select is_pr from gym_workout_summaries(5) s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w2'),
  false,
  'the PR judgement runs over all history, not just the returned page'
);

-- 6. exercise_count normalises names and drops the whitespace-only one.
select is(
  (select exercise_count from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w1'),
  3,
  'exercise_count is the distinct normalised exercise names in the workout'
);
select is(
  (select exercise_count from gym_workout_summaries() s
     join gym_workouts gw on gw.id = s.workout_id where gw.title = 'w2'),
  1,
  'a whitespace-only exercise name is not an exercise'
);

-- 7. …but it is still work performed, and /gym now takes its row stats from
--    the trigger-maintained totals, which count it. 60x5 + 50x5 = 550.
select is(
  (select set_count from gym_workouts where title = 'w2'),
  2,
  'set_count counts the whitespace-named set'
);
select is(
  (select volume_kg from gym_workouts where title = 'w2'),
  550::numeric,
  'volume_kg includes the whitespace-named set''s work'
);

-- 8. Newest first, matching the list order /gym renders.
select is(
  (select array_agg(gw.title order by t.ord)
     from gym_workout_summaries()
       with ordinality as t(workout_id, exercise_count, is_pr, ord)
     join gym_workouts gw on gw.id = t.workout_id),
  array['w6', 'w5', 'w4', 'w3', 'w2', 'w1'],
  'summaries are ordered newest-workout first'
);

-- 9. The Records-link gate is all-time and weight-aware.
select is(gym_has_weighted_sets(), true, 'a lifter with weighted sets gates the Records link open');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0002"}';
insert into gym_workouts (id, user_id, title, started_at)
values ('dddddddd-dddd-dddd-dddd-ddddddddddb1',
        '00000000-0000-0000-0000-0000000d0002', 'bw', now());
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values ('dddddddd-dddd-dddd-dddd-ddddddddddb1', 0, 'Push-up', 20, null);

select is(gym_has_weighted_sets(), false, 'a bodyweight-only lifter has no weighted sets');

-- 10. Owner-scoped: a stranger sees none of the lifter's workouts.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0099"}';
select is(
  (select count(*)::int from gym_workout_summaries()),
  0,
  'a different user sees none of the lifter''s summaries (owner-scoped)'
);

select * from finish();
rollback;
