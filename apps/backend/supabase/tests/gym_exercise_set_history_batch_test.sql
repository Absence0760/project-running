-- pgtap suite for `gym_exercise_set_history_batch` (migration 20270323_001).
--
-- The batched sibling of gym_exercise_set_history: one call serves N
-- exercises, matched on the NORMALISED name exactly like the singular RPC, and
-- tags each row with `normalised_name` so the client can group per input
-- exercise. Pin the same load-bearing properties as the singular suite plus
-- the batch-specific ones (grouping key, duplicate/blank inputs, owner scope).

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000b1001'::uuid, 'authenticated', 'authenticated',
   'lifter@bhist.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b1099'::uuid, 'authenticated', 'authenticated',
   'stranger@bhist.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000b1001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000b1099', 'Stranger');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b1001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc01',
   '00000000-0000-0000-0000-0000000b1001', 'A', now() - interval '2 days'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc02',
   '00000000-0000-0000-0000-0000000b1001', 'B', now() - interval '1 day');

insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc01', 0, 'Bench Press',  5, 60),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc01', 1, 'bench press',  5, 62),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc02', 0, '  Bench   Press ', 5, 65),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc02', 1, 'Overhead Press', 8, 40),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbc02', 2, 'Back Squat', 5, 100);

-- 1. One call serves two exercises; the un-asked-for third stays out.
select is(
  (select count(*)::int
     from gym_exercise_set_history_batch(array['Bench Press', 'Overhead Press'])),
  4,
  'a two-name batch returns both exercises'' sets and nothing else'
);

-- 2. Every bench spelling lands under the one normalised grouping key.
select is(
  (select count(*)::int
     from gym_exercise_set_history_batch(array['  bench   PRESS '])
     where normalised_name = 'bench press'),
  3,
  'differently-cased / spaced spellings group under the normalised key'
);

-- 3. Grouping keys partition the batch exactly.
select results_eq(
  $$select normalised_name, count(*)::int
      from gym_exercise_set_history_batch(array['Bench Press', 'Overhead Press'])
      group by normalised_name order by normalised_name$$,
  $$values ('bench press', 3), ('overhead press', 1)$$,
  'rows are tagged with the normalised name the client groups by'
);

-- 4. Duplicate spellings of one exercise in the input do not duplicate rows.
select is(
  (select count(*)::int
     from gym_exercise_set_history_batch(array['Bench Press', 'bench press'])),
  3,
  'duplicate input spellings collapse to one normalised key (no row dupes)'
);

-- 5. Null / blank / empty inputs return nothing rather than erroring.
select is(
  (select count(*)::int
     from gym_exercise_set_history_batch(array['', '   ', null])),
  0,
  'blank and null input names are ignored'
);

-- 6. Owner-scoped: a stranger sees none of the lifter's sets.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b1099"}';
select is(
  (select count(*)::int
     from gym_exercise_set_history_batch(array['Bench Press'])),
  0,
  'a different user sees none of the lifter''s sets (owner-scoped)'
);

select * from finish();
rollback;
