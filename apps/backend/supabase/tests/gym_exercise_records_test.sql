-- pgtap suite for `gym_exercise_records` (migrations 20261224_001,
-- 20270705000005).
--
-- The RPC is the SQL mirror of exercise_records.ts#exerciseRecords +
-- gym_prs.ts#computeExercisePrs — it replaces a client-side recompute over the
-- user's ENTIRE gym_sets history with one server-side aggregation. These
-- assertions pin the metrics against a controlled fixture so the SQL can't
-- drift from the TS engine (which gym_prs.test.ts pins on the other side).
--
-- Covers:
--   * heaviest weight + tie-break to most reps at that weight
--   * best single-set volume (reps · weight), independent of the heaviest set
--   * best Epley e1rm with the rep clamp, incl. the rounding case
--   * last_performed_at + distinct session_count
--   * bodyweight-only exercises excluded (no weighted record)
--   * ordering most-recently-performed first, display-name tiebreak
--   * the display spelling for a key: the caller's MOST-RECENT one, and among
--     spellings logged at the same instant, the one without a paste artefact
--     (the rule 20270705000005 unified with `gym_exercise_names`, § 1050)
--   * owner-scoping (a stranger sees none of this user's records)

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000a0001'::uuid, 'authenticated', 'authenticated',
   'lifter@records.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000a0099'::uuid, 'authenticated', 'authenticated',
   'stranger@records.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000a0001', 'Lifter'),
  ('00000000-0000-0000-0000-0000000a0099', 'Stranger');

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000a0001"}';

-- Two workouts. w1 (earlier): Bench 60x5 + Bench 60x8 (tie weight, more reps)
-- + OHP 40x8 + Pull-up 10xNULL (bodyweight, must be excluded). w2 (later):
-- Squat 100x5.
insert into gym_workouts (id, user_id, title, started_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01',
   '00000000-0000-0000-0000-0000000a0001', 'Upper', now() - interval '2 days'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02',
   '00000000-0000-0000-0000-0000000a0001', 'Lower', now() - interval '1 day'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa00',
   '00000000-0000-0000-0000-0000000a0001', 'Oldest', now() - interval '3 days');

insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 0, 'Bench Press', 5, 60),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 1, 'Bench Press', 8, 60),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 2, 'Overhead Press', 8, 40),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 3, 'Pull-up', 10, null),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 0, 'Back Squat', 5, 100),
  -- One key under three spellings, for the display-spelling rule. `DEADLIFT`
  -- is the most-USED and sits in the oldest session; the two in the newest
  -- session are equally recent, so only `length(display)` separates them.
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa00', 0, 'DEADLIFT', 5, 140),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa00', 1, 'DEADLIFT', 5, 140),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 1, chr(9) || 'Deadlift', 5, 145),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 2, 'Deadlift', 5, 145);

-- 1. Four weighted exercises; the bodyweight Pull-up is excluded, and the
--    three deadlift spellings are one record rather than three.
select is(
  (select count(*)::int from gym_exercise_records()),
  4,
  'bodyweight-only exercise (Pull-up) is excluded; 4 weighted records remain'
);

-- 2. Bench heaviest weight is 60 with the tie broken to the most reps (8).
select is(
  (select heaviest_weight_reps from gym_exercise_records() where exercise_name = 'Bench Press'),
  8,
  'heaviest-weight reps tie-breaks to the most reps at that weight'
);

-- 3. Bench best volume is the heavier-volume set (60x8 = 480), not the 60x5.
select is(
  (select best_volume_kg from gym_exercise_records() where exercise_name = 'Bench Press'),
  480.0::numeric,
  'best volume is max(reps*weight) across sets, independent of heaviest weight'
);

-- 4. Bench best e1rm = 60*(1 + 8/30) = 76.0 (Epley).
select is(
  (select best_est_1rm_kg from gym_exercise_records() where exercise_name = 'Bench Press'),
  76.0::numeric,
  'best e1rm uses the Epley formula on the best rep set'
);

-- 5. OHP e1rm = 40*(1 + 8/30) = 50.666… → rounded to 50.7 (the rounding case).
select is(
  (select best_est_1rm_kg from gym_exercise_records() where exercise_name = 'Overhead Press'),
  50.7::numeric,
  'e1rm rounds to 1 dp matching round1() in gym_prs.ts'
);

-- 6. Squat session_count = 1 (one workout includes it).
select is(
  (select session_count from gym_exercise_records() where exercise_name = 'Back Squat'),
  1,
  'session_count is distinct workouts including the exercise'
);

-- 7. Bench session_count = 1 (both bench sets are in the same workout).
select is(
  (select session_count from gym_exercise_records() where exercise_name = 'Bench Press'),
  1,
  'two sets of one exercise in one workout count as a single session'
);

-- 8. Squat heaviest weight = 100.
select is(
  (select heaviest_weight_kg from gym_exercise_records() where exercise_name = 'Back Squat'),
  100::numeric,
  'heaviest weight is the max weight_kg'
);

-- 9. Ordering: most-recently-performed first. Squat (w2, later) leads.
select is(
  (select exercise_name from gym_exercise_records() limit 1),
  'Back Squat',
  'records are ordered most-recently-performed first'
);

-- 10. The display spelling is the caller's MOST-RECENT one, not their
--     most-used one: `DEADLIFT` has two sets against the newer session's one
--     each, and loses. This is the rule `gym_exercise_names` was brought onto
--     in 20270705000005; it was already this RPC's rule and does not move.
select is(
  (select exercise_name from gym_exercise_records()
   where public.normalise_exercise_name(exercise_name) = 'deadlift'),
  'Deadlift',
  'the display spelling is the most-recent one, not the most-used'
);

-- 11. And the equally-recent paste artefact never surfaces. Without
--     `length(display)` the pick between two same-instant spellings falls to
--     the argument's own collation, which is the dependence § 830 closed for
--     the key itself.
select is(
  (select count(*)::int from gym_exercise_records()
   where exercise_name like chr(9) || '%'),
  0,
  'a same-instant paste artefact loses to its clean sibling'
);

-- 12. Owner-scoped: a stranger sees none of this user's records.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000a0099"}';
select is(
  (select count(*)::int from gym_exercise_records()),
  0,
  'a different user sees none of the lifter''s records (owner-scoped)'
);

select * from finish();
rollback;
