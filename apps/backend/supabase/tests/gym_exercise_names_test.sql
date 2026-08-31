-- pgtap suite for `gym_exercise_names` (migrations 20261226_001, 20270630000004).
--
-- Returns the caller's distinct logged exercises + use counts, most-used
-- first, for the gym editor autocomplete — so a caller that only needs the
-- names never pulls raw set history.
--
-- Covers:
--   1. Correct use counts, ordered most-used first.
--   2. Grouping is the canonical key, not the spelling, so a case variant and
--      a stray-whitespace paste are one suggestion rather than three
--      (decisions § 831). Before 20270630000004 the grouping was a bare
--      `btrim`, which strips U+0020 alone.
--   3. The display spelling is the caller's MOST-USED one, which is not the
--      most-recent one the sibling `gym_exercise_records` picks.
--   4. Owner-scoped (a stranger sees none of the caller's names).

begin;

select plan(6);

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

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01',
   '00000000-0000-0000-0000-0000000c0001', 'older', now() - interval '2 days'),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02',
   '00000000-0000-0000-0000-0000000c0001', 'newer', now() - interval '1 day');

-- One lift under three spellings across two sessions. `Bench Press` is the
-- most-USED (2 sets) and the older one; `bench press` and the tab-prefixed
-- paste are each the most-RECENT, which is the spelling the sibling RPC's
-- ordering would pick. Squat leads the list on count alone.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 0, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 1, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 2, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 3, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 4, 'Squat', 5, 100),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 5, 'Bench Press', 5, 60),
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 6, 'Bench Press', 5, 60),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 0, 'bench press', 5, 62),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 1, chr(9) || 'Bench Press', 5, 62);

-- 1. Most-used first: Squat (5) leads.
select is(
  (select exercise_name from gym_exercise_names() limit 1),
  'Squat',
  'names are ordered most-used first'
);

-- 2. Squat use count is 5.
select is(
  (select uses from gym_exercise_names() where exercise_name = 'Squat'),
  5,
  'use count is the number of sets logged under that name'
);

-- 3. The whole point of 20270630000004. Grouped on the spelling, the four
--    bench sets were THREE suggestions: two differing only in case, and one
--    differing only by an invisible leading tab that `btrim` does not strip.
select is(
  (select count(*)::int from gym_exercise_names()),
  2,
  'one suggestion per exercise, not one per spelling of it'
);

-- 4. And the count beside it is how often the LIFT was logged, not how often
--    one spelling of it was: 2 + 1 + 1.
select is(
  (select uses from gym_exercise_names()
   where public.normalise_exercise_name(exercise_name) = 'bench press'),
  4,
  'uses counts every spelling in the group'
);

-- 5. The spelling shown is the most-USED one. Ordering by started_at desc --
--    what `gym_exercise_records` does, and what the filing believed this fix
--    would be reusing -- picks a spelling from the newer session instead, so
--    this assertion fails under that rule rather than merely passing under
--    both. The tab-prefixed paste never surfaces.
select is(
  (select exercise_name from gym_exercise_names()
   where public.normalise_exercise_name(exercise_name) = 'bench press'),
  'Bench Press',
  'the display spelling is the most-used one, not the most-recent'
);

-- 6. Owner-scoped: a stranger sees none of the lifter's names.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0099"}';
select is(
  (select count(*)::int from gym_exercise_names()),
  0,
  'a different user sees none of the lifter''s names (owner-scoped)'
);

select * from finish();
rollback;
