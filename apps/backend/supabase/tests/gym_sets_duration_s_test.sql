-- pgtap suite for gym_sets.duration_s (migration 20261231_001).
--
-- duration_s makes timed work (planks, holds, intervals) first-class on a set.
-- It is nullable and non-negative. Pins:
--   1. The CHECK rejects a negative duration.
--   2. NULL is accepted (every existing rep/load set keeps working).
--   3. A non-negative value (90 s plank) is accepted + round-trips.
--   4. gym_exercise_set_history returns the column for the progression view.

begin;

select plan(5);

-- Column exists with the expected type.
select has_column('public', 'gym_sets', 'duration_s', 'gym_sets has a duration_s column');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000d0001'::uuid, 'authenticated', 'authenticated',
   'plank@dur.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000d0001', 'Planker');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01',
   '00000000-0000-0000-0000-0000000d0001', 'Core', now() - interval '1 day');

-- 1. A negative duration is rejected by the CHECK.
select throws_ok(
  $$insert into gym_sets (workout_id, set_index, exercise_name, duration_s)
    values ('dddddddd-dddd-dddd-dddd-dddddddddd01', 0, 'Plank', -1)$$,
  '23514',
  null,
  'a negative duration_s is rejected by the CHECK'
);

-- 2. NULL is accepted (rep/load-only set).
select lives_ok(
  $$insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
    values ('dddddddd-dddd-dddd-dddd-dddddddddd01', 1, 'Squat', 5, 100)$$,
  'a set with a null duration_s is accepted'
);

-- 3. A 90 s hold is accepted and stored.
insert into gym_sets (workout_id, set_index, exercise_name, duration_s)
values ('dddddddd-dddd-dddd-dddd-dddddddddd01', 2, 'Plank', 90);
select is(
  (select duration_s from gym_sets
     where workout_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'
       and exercise_name = 'Plank'),
  90,
  'a 90 s hold round-trips into duration_s'
);

-- 4. The set-history RPC surfaces duration_s for the progression view.
select is(
  (select duration_s from gym_exercise_set_history('Plank')),
  90,
  'gym_exercise_set_history returns the set duration_s'
);

select * from finish();
rollback;
