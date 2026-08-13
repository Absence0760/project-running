-- pgtap suite for `gym_exercise_set_history` (migration 20261225_001).
--
-- The RPC returns one exercise's sets for the /gym/exercise progression view,
-- matched on the NORMALISED name (trim → lowercase → collapse whitespace) so
-- the bounded server read picks up exactly the sessions the old client-side
-- exerciseProgress() grouped together. The load-bearing property an exact `=`
-- filter would get wrong is the case/whitespace-insensitive match — pin it.
--
-- Covers:
--   1. Differently-cased / spaced spellings of the same exercise all match.
--   2. A different exercise does not match.
--   3. Owner-scoped (a stranger sees none of the user's sets).
--   4. Each row carries its logged set_type (migration 20270525_001).

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000b0001'::uuid, 'authenticated', 'authenticated',
   'lifter@hist.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b0099'::uuid, 'authenticated', 'authenticated',
   'stranger@hist.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000b0001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000b0099', 'Stranger');

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
   '00000000-0000-0000-0000-0000000b0001', 'A', now() - interval '2 days'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02',
   '00000000-0000-0000-0000-0000000b0001', 'B', now() - interval '1 day');

-- Three spellings of one exercise + a different exercise.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 0, 'Bench Press',  5, 60),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 1, 'bench press',  5, 62),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 0, '  Bench   Press ', 5, 65),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 1, 'Overhead Press', 8, 40);

-- A warmup logged AT the working weight — the case only the label separates.
-- On its own exercise so the counting assertions above are untouched.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg, set_type)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 2, 'Deadlift', 2, 140, 'warmup'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 3, 'Deadlift', 5, 140, 'working');

-- 1. All three bench spellings match the normalised key (exact `=` would only
--    catch one).
select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  3,
  'differently-cased / spaced spellings of the same exercise all match'
);

-- 2. The match is case/whitespace-insensitive from the query side too.
select is(
  (select count(*)::int from gym_exercise_set_history('   bench PRESS  ')),
  3,
  'the query name is normalised the same way as the stored names'
);

-- 3. A different exercise does not bleed in.
select is(
  (select count(*)::int from gym_exercise_set_history('Overhead Press')),
  1,
  'a different exercise returns only its own sets'
);

-- 4. Each row carries the set_type it was logged with (migration 20270525_001).
select results_eq(
  $$select set_type from gym_exercise_set_history('Deadlift') order by set_type$$,
  $$values ('warmup'), ('working')$$,
  'each row carries its logged set_type'
);

-- 5. gym_sets.set_type is NOT NULL DEFAULT 'working' (20270228_001), so a set
--    logged without an explicit type reads back as 'working', never null.
select is(
  (select count(*)::int
     from gym_exercise_set_history('Bench Press')
     where set_type is distinct from 'working'),
  0,
  'sets logged with no explicit type read back as ''working'', never null'
);

-- 6. Owner-scoped: a stranger sees none of the lifter's sets.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0099"}';
select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  0,
  'a different user sees none of the lifter''s sets (owner-scoped)'
);

select * from finish();
rollback;
