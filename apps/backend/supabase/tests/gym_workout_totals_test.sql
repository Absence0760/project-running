-- Pins F7: gym_workouts.set_count / volume_kg are trigger-maintained from
-- gym_sets (20261214_001), and the activities view reads the columns.
--
-- Exercises insert / update / delete of sets and asserts both the stored
-- columns and the view's summary jsonb track the authoritative count/sum.
-- Runs as superuser so RLS is out of the way.

begin;

select plan(9);

insert into gym_workouts (id, user_id, title)
  values ('f7000000-0000-0000-0000-000000000001',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Leg Day');

-- A fresh workout with no sets reads 0 / 0.
select is(
  (select set_count from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  0,
  'a workout with no sets has set_count 0'
);
select is(
  (select volume_kg from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  0::numeric,
  'a workout with no sets has volume_kg 0'
);

-- Two sets: 5 reps * 100kg + 5 reps * 80kg = 900kg over 2 sets.
insert into gym_sets (id, workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('f7aaaaaa-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 1, 'Squat', 5, 100),
  ('f7aaaaaa-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000001', 2, 'Squat', 5, 80);

select is(
  (select set_count from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  2,
  'inserting two sets bumps set_count to 2'
);
select is(
  (select volume_kg from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  900::numeric,
  'volume_kg sums reps * weight_kg = 900'
);

-- The view reads the columns.
select is(
  (select (summary ->> 'set_count')::int from activities
     where id = 'f7000000-0000-0000-0000-000000000001' and kind = 'lift'),
  2,
  'activities view set_count matches the stored column'
);
select is(
  (select (summary ->> 'volume_kg')::numeric from activities
     where id = 'f7000000-0000-0000-0000-000000000001' and kind = 'lift'),
  900::numeric,
  'activities view volume_kg matches the stored column'
);

-- Update a set's weight: 5*120 + 5*80 = 1000.
update gym_sets set weight_kg = 120
  where id = 'f7aaaaaa-0000-0000-0000-000000000001';
select is(
  (select volume_kg from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  1000::numeric,
  'updating a set recomputes volume_kg to 1000'
);

-- Delete the squat set: only the 5*80 = 400kg set remains.
delete from gym_sets where id = 'f7aaaaaa-0000-0000-0000-000000000001';
select is(
  (select set_count from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  1,
  'deleting a set drops set_count to 1'
);
select is(
  (select volume_kg from gym_workouts where id = 'f7000000-0000-0000-0000-000000000001'),
  400::numeric,
  'deleting a set drops volume_kg to 400'
);

select * from finish();
rollback;
