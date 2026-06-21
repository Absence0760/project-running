-- pgtap suite for gym_sets.set_type (migration 20270224_001).
--
-- set_type records the role a LOGGED set played, reusing the
-- gym_routine_sets.set_type vocabulary + CHECK (20270101_001). It is NOT NULL
-- with a 'working' default. Pins:
--   1. The column exists.
--   2. An out-of-vocabulary value is rejected by the CHECK.
--   3. An omitted set_type defaults to 'working'.
--   4. Each in-vocabulary value is accepted + round-trips.

begin;

select plan(4);

-- 1. Column exists.
select has_column('public', 'gym_sets', 'set_type', 'gym_sets has a set_type column');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000e0001'::uuid, 'authenticated', 'authenticated',
   'settype@gym.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000e0001', 'Lifter');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
   '00000000-0000-0000-0000-0000000e0001', 'Legs', now() - interval '1 day');

-- 2. An out-of-vocabulary set_type is rejected by the CHECK.
select throws_ok(
  $$insert into gym_sets (workout_id, set_index, exercise_name, set_type)
    values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 0, 'Squat', 'megaset')$$,
  '23514',
  null,
  'an out-of-vocabulary set_type is rejected by the CHECK'
);

-- 3. An omitted set_type defaults to 'working'.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 1, 'Squat', 5, 100);
select is(
  (select set_type from gym_sets
     where workout_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' and set_index = 1),
  'working',
  'an omitted set_type defaults to working'
);

-- 4. Each in-vocabulary value is accepted + round-trips.
insert into gym_sets (workout_id, set_index, exercise_name, set_type)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 2, 'Squat', 'warmup'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 3, 'Squat', 'dropset'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 4, 'Squat', 'amrap'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 5, 'Squat', 'failure'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 6, 'Squat', 'backoff');
select bag_eq(
  $$select set_type from gym_sets
      where workout_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' and set_index between 2 and 6$$,
  $$values ('warmup'),('dropset'),('amrap'),('failure'),('backoff')$$,
  'every in-vocabulary set_type value is accepted'
);

select * from finish();
rollback;
