-- pgtap suite for `gym_exercise_names` (migration 20261226_001).
--
-- Returns the user's distinct logged exercise names + use counts, most-used
-- first, for the gym editor autocomplete — so a caller that only needs the
-- names never pulls raw set history.
--
-- Covers:
--   1. Distinct trimmed names with correct use counts, ordered most-used first.
--   2. Case-preserved (trim only) — "Bench Press" and "bench press" stay
--      distinct, matching the prior client behaviour.
--   3. Owner-scoped (a stranger sees none of the user's names).

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c0001'::uuid, 'authenticated', 'authenticated',
   'lifter@names.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0099'::uuid, 'authenticated', 'authenticated',
   'stranger@names.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000c0001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000c0099', 'Stranger');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01',
   '00000000-0000-0000-0000-0000000c0001', 'W', now() - interval '1 day');

-- Squat x3, Bench Press x1, bench press x1 (different case → distinct).
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 0, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 1, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 2, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 3, 'Bench Press', 5, 60),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 4, 'bench press', 5, 62);

-- 1. Most-used first: Squat (3) leads.
select is(
  (select exercise_name from gym_exercise_names() limit 1),
  'Squat',
  'names are ordered most-used first'
);

-- 2. Squat use count is 3.
select is(
  (select uses from gym_exercise_names() where exercise_name = 'Squat'),
  3,
  'use count is the number of sets logged under that name'
);

-- 3. Case-preserved: the two bench spellings stay distinct (3 names total).
select is(
  (select count(*)::int from gym_exercise_names()),
  3,
  'case-preserved names stay distinct ("Bench Press" vs "bench press")'
);

-- 4. Owner-scoped: a stranger sees none of the lifter's names.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0099"}';
select is(
  (select count(*)::int from gym_exercise_names()),
  0,
  'a different user sees none of the lifter''s names (owner-scoped)'
);

select * from finish();
rollback;
