-- pgtap suite for the persisted `gym_sets.exercise_key` (migrations
-- 20270706000001 + 20270706000002).
--
-- The exercise grouping key used to be re-derived once per `gym_sets` row
-- inside every one of the five RPCs that group a lifter's history. It is now a
-- column, stamped by a BEFORE INSERT OR UPDATE trigger, and the RPCs read it.
-- Two properties have to hold or a lifter's history splits silently:
--
--   * the stored key can never disagree with the name it groups -- the trigger
--     derives it unconditionally, so a client value is OVERWRITTEN rather than
--     refused, and the CHECK behind it is validated rather than merely declared
--   * the RPCs actually read the column. A body that still folded the name
--     would pass every bucketing assertion below while leaving the cost this
--     change exists to remove, so test 13 takes the column away from the name
--     and proves each answer follows the COLUMN.
--
-- Everything here runs inside the suite's own transaction and is rolled back.

begin;

select plan(13);

-- ── The column and its invariant ────────────────────────────────────────────

-- 1. Nullable would let the canonical CHECK pass on a NULL: `null = <text>` is
--    NULL, and a CHECK evaluating to NULL passes. Such a row would then be
--    dropped from every aggregate rather than mis-bucketed -- worse, because
--    nothing surfaces it. It is also what makes the generated row types
--    non-nullable on all three clients.
select col_not_null('public', 'gym_sets', 'exercise_key',
  'gym_sets.exercise_key is NOT NULL');

-- 2. A constraint added `not valid` and never validated makes a claim about new
--    rows only, so the rows already in the table are outside it.
select is(
  (select convalidated from pg_constraint
   where conrelid = 'public.gym_sets'::regclass
     and conname = 'gym_sets_exercise_key_canonical'),
  true,
  'the canonical CHECK is validated, not merely declared'
);

-- ── The trigger ─────────────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000c0001'::uuid, 'authenticated', 'authenticated',
        'lifter@setkey.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000c0001', 'Lifter');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('00000000-0000-0000-0000-0000000c1001', '00000000-0000-0000-0000-0000000c0001',
   'w1', now() - interval '4 days'),
  ('00000000-0000-0000-0000-0000000c1002', '00000000-0000-0000-0000-0000000c0001',
   'w2', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000c1003', '00000000-0000-0000-0000-0000000c0001',
   'w3', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000c1004', '00000000-0000-0000-0000-0000000c0001',
   'w4', now() - interval '1 day');

-- 3. The key is the server's answer, not the client's. A client that sends one
--    -- with an older Unicode case table, or with none at all -- has it
--    replaced. That is the difference from `gym_routine_exercises.exercise_key`,
--    where the client stamps it under a CHECK and a 23514 on a legitimate save
--    was reachable (decisions § 830).
insert into gym_sets (id, workout_id, set_index, exercise_name, exercise_key, reps, weight_kg)
values ('00000000-0000-0000-0000-0000000c2001',
        '00000000-0000-0000-0000-0000000c1001', 0, 'Bench Press', 'NOT THE KEY', 5, 60);

select is(
  (select exercise_key from gym_sets where id = '00000000-0000-0000-0000-0000000c2001'),
  'bench press',
  'a client-supplied exercise_key is overwritten by the trigger, not refused'
);

-- 4. Renaming the exercise moves the key with it. Without this the set stays in
--    the old bucket for ever.
update gym_sets set exercise_name = 'Incline Bench Press'
 where id = '00000000-0000-0000-0000-0000000c2001';

select is(
  (select exercise_key from gym_sets where id = '00000000-0000-0000-0000-0000000c2001'),
  'incline bench press',
  'renaming the exercise re-stamps the key'
);

-- 5. The reason the trigger is `before insert or update` and not
--    `... update of exercise_name`: an UPDATE that names only the key would not
--    fire the narrower form, and the canonical CHECK would then answer with a
--    23514 the client cannot act on.
update gym_sets set exercise_key = 'something else'
 where id = '00000000-0000-0000-0000-0000000c2001';

select is(
  (select exercise_key from gym_sets where id = '00000000-0000-0000-0000-0000000c2001'),
  'incline bench press',
  'an UPDATE naming only exercise_key is re-stamped, not rejected'
);

update gym_sets set exercise_name = 'Bench Press'
 where id = '00000000-0000-0000-0000-0000000c2001';

-- 6. A name that is nothing but whitespace is not an exercise. It stamps the
--    empty key, which is what the RPCs' `exercise_key <> ''` filter excludes --
--    the same rows `coalesce(normalise(...), '') <> ''` excluded before.
insert into gym_sets (id, workout_id, set_index, exercise_name, reps)
values ('00000000-0000-0000-0000-0000000c2009',
        '00000000-0000-0000-0000-0000000c1001', 9, chr(9) || chr(160), 5);

select is(
  (select exercise_key from gym_sets where id = '00000000-0000-0000-0000-0000000c2009'),
  '',
  'a whitespace-only name stamps the empty key'
);

-- 7. The trigger calls `normalise_exercise_name` as the WRITING role, exactly
--    as the CHECK constraints do, so the same 42501 that broke every
--    service_role write to the two keyed tables is reachable here (§ 790). The
--    Playwright gym fixtures insert as service_role.
set local role service_role;
select lives_ok(
  $$insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
    values ('00000000-0000-0000-0000-0000000c1001', 8, 'Front Squat', 5, 50)$$,
  'a service_role insert can evaluate the trigger''s fold'
);
set local role authenticated;

-- ── The five readers, on the persisted key ──────────────────────────────────
-- One lift under four spellings a paste can produce, mirroring
-- normalise_exercise_name_test.sql: w2 repeats it tab-prefixed at a heavier
-- weight (a real PR), w3 with an internal NBSP and w4 with an internal U+FEFF,
-- both below the w2 best and so neither a PR.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('00000000-0000-0000-0000-0000000c1002', 0, chr(9) || 'Bench Press', 5, 80),
  ('00000000-0000-0000-0000-0000000c1003', 0, 'Bench' || chr(160) || 'Press', 5, 65),
  ('00000000-0000-0000-0000-0000000c1004', 0, 'Bench' || chr(65279) || 'Press', 5, 70);

-- 8.
select is(
  (select session_count from gym_exercise_records() where exercise_name like 'Bench%'),
  4,
  'gym_exercise_records buckets the four spellings as one exercise'
);

-- 9.
select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  4,
  'gym_exercise_set_history returns all four sets for the plain spelling'
);

-- 10.
select is(
  (select distinct normalised_name
   from gym_exercise_set_history_batch(array[chr(9) || 'BENCH  PRESS'])),
  'bench press',
  'gym_exercise_set_history_batch returns the canonical key, not a variant'
);

-- 11. The whitespace-only set from 6 lives in w1 and must not count as a second
--     exercise there, and the Front Squat from 7 must.
select is(
  (select exercise_count from gym_workout_summaries()
   where workout_id = '00000000-0000-0000-0000-0000000c1001'),
  2,
  'gym_workout_summaries excludes the empty key from the exercise count'
);

-- 12. w4 repeats the lift 10 kg below the w2 best, so it sets nothing.
select is(
  (select is_pr from gym_workout_summaries()
   where workout_id = '00000000-0000-0000-0000-0000000c1004'),
  false,
  'a lift re-logged under a variant spelling below its best is not a PR'
);

-- ── The mutation ────────────────────────────────────────────────────────────

-- 13. Every assertion above passes just as well against a body that still folds
--     `exercise_name` per row, which is the cost this change exists to remove.
--     Take the column away from the name -- trigger off, CHECK dropped, both
--     rolled back with the suite -- and each RPC's answer has to follow the
--     COLUMN. If a body still derived the key, w2's set would stay in the bench
--     press bucket and the count would read 4.
reset role;
alter table public.gym_sets disable trigger gym_sets_stamp_exercise_key_trigger;
alter table public.gym_sets drop constraint gym_sets_exercise_key_canonical;
update gym_sets set exercise_key = 'moved elsewhere'
 where workout_id = '00000000-0000-0000-0000-0000000c1002';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';

select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  3,
  'the RPCs read the stored key, not the name they could re-fold'
);

select * from finish();
rollback;
