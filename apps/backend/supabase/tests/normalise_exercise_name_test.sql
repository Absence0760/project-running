-- pgtap suite for `public.normalise_exercise_name` (migration 20270623000001).
--
-- The exercise grouping key is derived on three rails — this function, web's
-- `normaliseExerciseName` in gym_prs.ts, and mobile's in gym_prs.dart — and the
-- clients PERSIST it as `gym_routine_exercises.exercise_key` /
-- `exercises.name_key`. A name the server buckets differently from the clients
-- splits one exercise into two: the local PR tracker says PR where
-- `gym_workout_summaries.is_pr` says no, and `gym_exercise_set_history(p_name)`
-- returns an empty history for a lift that has one (decisions § 790).
--
-- Every string here is built with `chr()` rather than an escape so the file
-- carries no invisible character a diff would hide.
--
-- Covers:
--   * the six cases the old `regexp_replace(lower(btrim(x)), '\s+', ' ', 'g')`
--     got wrong, each pinned to the exact answer both client suites assert
--   * that the derivation does not depend on the database's locale provider,
--     which the old one did — `\s` past ASCII is `[[:space:]]`, and the ICU and
--     libc providers disagree about U+00A0 / U+2007 / U+202F / U+001C-U+001F
--   * that the four live RPCs bucket the variant spellings with the plain one
--   * that a workout re-logging a lift under a variant spelling is not scored
--     as a fresh personal record
--   * that the two CHECK constraints reject a non-canonical stored key, and
--     that every role able to write the keyed tables may evaluate them -- a
--     CHECK naming a function ACL-checks it against the INSERTING role

begin;

select plan(17);

-- ── The pure derivation ─────────────────────────────────────────────────────

-- 1. btrim(text) strips U+0020 alone, so a leading TAB survived the trim and
--    the \s+ pass turned it into a leading SPACE: ' bench press'.
select is(
  public.normalise_exercise_name(chr(9) || 'Bench Press'),
  'bench press',
  'a leading tab is trimmed, not converted into a leading space'
);

-- 2. Same shape at the other end, for the newline a paste carries.
select is(
  public.normalise_exercise_name('Bench Press' || chr(10)),
  'bench press',
  'a trailing newline is trimmed, not converted into a trailing space'
);

-- 3. A pasted NBSP. Folded here under every provider, where `\s` folded it
--    only under ICU.
select is(
  public.normalise_exercise_name('Bench' || chr(160) || 'Press'),
  'bench press',
  'U+00A0 folds to a space'
);

-- 4. U+FEFF is not Unicode White_Space and no provider's `\s` matched it, but
--    it is invisible and must not split a bucket. Both clients fold it.
select is(
  public.normalise_exercise_name('Bench' || chr(65279) || 'Press'),
  'bench press',
  'U+FEFF folds to a space'
);

-- 5. A name that is nothing but whitespace is not an exercise. The old
--    blank-name filter `btrim(coalesce(name,'')) <> ''` kept a lone tab as an
--    exercise named " "; both clients always dropped it.
select is(
  public.normalise_exercise_name(chr(9) || chr(160)),
  '',
  'a whitespace-only name normalises to the empty key'
);

-- 6. The ICU provider's `\s` also matches U+001C-U+001F. Those are control
--    characters, not spaces — closing the divergence meant the SERVER stopping,
--    not the clients starting.
select is(
  public.normalise_exercise_name('Bench' || chr(28) || 'Press'),
  'bench' || chr(28) || 'press',
  'U+001C is preserved, matching both clients'
);

-- ── Provider independence ───────────────────────────────────────────────────

-- 7. The old expression's answer moved with the database's locale provider, so
--    the same migration set produced different keys on two deployments. The
--    class is written by code point now, so it cannot.
select is(
  (select bool_and(
     public.normalise_exercise_name(s)
       = public.normalise_exercise_name(s collate "en_US.utf8"))
   from (values
     (chr(9) || 'Bench Press'),
     ('Bench Press' || chr(10)),
     ('Bench' || chr(160) || 'Press'),
     ('Bench' || chr(8199) || 'Press'),
     ('Bench' || chr(8239) || 'Press'),
     ('Bench' || chr(65279) || 'Press'),
     ('Bench' || chr(28) || 'Press')
   ) as t(s)),
  true,
  'the key does not depend on the database locale provider'
);

-- ── The RPCs that re-derive it ──────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000b0001'::uuid, 'authenticated', 'authenticated',
        'lifter@normalise.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000b0001', 'Lifter');

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';

-- Four workouts logging ONE lift under four spellings a paste can produce.
-- w1 is the plain name; w2 repeats it tab-prefixed at a HEAVIER weight (a real
-- PR); w3 repeats it with an internal NBSP; w4 with an internal U+FEFF, both
-- below the w2 best and so neither a PR. Under the old derivation w2 and w4
-- were each a brand-new exercise, and a first sighting is a PR on all three
-- metrics by definition. The tab and the U+FEFF cases are chosen because they
-- split the bucket under BOTH locale providers; NBSP splits it only under libc.
insert into gym_workouts (id, user_id, title, started_at)
values
  ('00000000-0000-0000-0000-0000000b1001', '00000000-0000-0000-0000-0000000b0001',
   'w1', now() - interval '4 days'),
  ('00000000-0000-0000-0000-0000000b1002', '00000000-0000-0000-0000-0000000b0001',
   'w2', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000b1003', '00000000-0000-0000-0000-0000000b0001',
   'w3', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000b1004', '00000000-0000-0000-0000-0000000b0001',
   'w4', now() - interval '1 day');

insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('00000000-0000-0000-0000-0000000b1001', 0, 'Bench Press', 5, 60),
  ('00000000-0000-0000-0000-0000000b1002', 0, chr(9) || 'Bench Press', 5, 80),
  ('00000000-0000-0000-0000-0000000b1003', 0, 'Bench' || chr(160) || 'Press', 5, 65),
  ('00000000-0000-0000-0000-0000000b1004', 0, 'Bench' || chr(65279) || 'Press', 5, 70);

-- 8. One exercise, four sessions — not four exercises with one session each.
select is(
  (select session_count from gym_exercise_records()
   where public.normalise_exercise_name(exercise_name) = 'bench press'),
  4,
  'gym_exercise_records buckets the four spellings as one exercise'
);

-- 9. The history RPC finds every set for the lift whatever spelling reached the
--    database, and whatever spelling the caller asks with.
select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  4,
  'gym_exercise_set_history returns all four sets for the plain spelling'
);

-- 10. The batch RPC's returned key is what the client joins its rows on, so it
--     has to BE the canonical key rather than merely be consistent with itself.
--     The old expression answered ' bench press' here, with a leading space.
select is(
  (select distinct normalised_name
   from gym_exercise_set_history_batch(array[chr(9) || 'BENCH  PRESS'])),
  'bench press',
  'gym_exercise_set_history_batch returns the canonical key, not a variant'
);

-- 11. The money assertion. w4 repeats the lift 10 kg BELOW the w2 best, so it
--     sets nothing. Keyed as its own exercise it was a first sighting, and a
--     first sighting is a PR on all three metrics — a false badge on the
--     History row, against a local PR tracker that correctly said no.
select is(
  (select is_pr from gym_workout_summaries()
   where workout_id = '00000000-0000-0000-0000-0000000b1004'),
  false,
  'a lift re-logged under a variant spelling below its best is not a PR'
);

-- 12. The positive control for 11: a genuine 60 -> 80 kg jump still reads as a
--     PR, so the assertion above cannot be passing because nothing is.
select is(
  (select is_pr from gym_workout_summaries()
   where workout_id = '00000000-0000-0000-0000-0000000b1002'),
  true,
  'a genuine heaviest-weight jump is still reported as a PR'
);

-- ── The stored key ──────────────────────────────────────────────────────────

insert into gym_routines (id, author_id, title)
values ('00000000-0000-0000-0000-0000000b2001',
        '00000000-0000-0000-0000-0000000b0001', 'Push day');

-- 13. The invariant is the database's now, not a convention four surfaces have
--     to remember. ' bench press' is exactly what the old server expression
--     derived from this name.
select throws_ok(
  $$insert into gym_routine_exercises (routine_id, exercise_name, exercise_key, position)
    values ('00000000-0000-0000-0000-0000000b2001', E'\tBench Press', ' bench press', 0)$$,
  '23514',
  null,
  'a stored exercise_key that is not the canonical derivation is rejected'
);

-- 14. The CHECK is evaluated as the role doing the INSERT, and it names a
--     function, so that role needs EXECUTE on it. Granted to `authenticated`
--     alone, every service_role write to these two tables failed with 42501 --
--     the Playwright gym fixtures insert exactly this way. `anon` is correctly
--     absent: RLS lets it write neither table, and a CHECK only runs on a write.
select is(
  (select array_agg(r order by r)
   from (values ('authenticated'), ('service_role'), ('anon')) as t(r)
   where has_function_privilege(r, 'public.normalise_exercise_name(text)', 'EXECUTE')),
  array['authenticated', 'service_role'],
  'exactly the roles that can write the two keyed tables may evaluate the CHECK'
);

-- 15. And the write itself, as service_role, which is what 14 is about.
set local role service_role;
select lives_ok(
  $$insert into gym_routine_exercises (routine_id, exercise_name, exercise_key, position)
    values ('00000000-0000-0000-0000-0000000b2001', 'Front Squat', 'front squat', 1)$$,
  'a service_role insert satisfying the constraint is not refused by it'
);

-- ── the whole class, one code point at a time ──────────────────────────────
-- The six named cases above are the ones the old expression got wrong. This
-- walks every member of the class the three rails share, because a migration
-- that dropped one code point from the SQL copy alone would split exactly the
-- names carrying it and nothing else in this file would notice. Each is
-- checked both as an interior separator and at both edges, since the old
-- defect was precisely a trim that did not cover what the fold produced.
select is(
  (select count(*)::int
     from unnest(array[
       9, 10, 11, 12, 13, 32, 133, 160, 5760,
       8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202,
       8232, 8233, 8239, 8287, 12288, 65279
     ]) as cp
    where public.normalise_exercise_name('Bench' || chr(cp) || 'Press') <> 'bench press'
       or public.normalise_exercise_name(chr(cp) || 'Bench Press' || chr(cp)) <> 'bench press'),
  0,
  'every code point in the shared whitespace class folds to a space and trims'
);

-- The deliberate exclusions, kept out on all three rails: U+001C-U+001F are
-- control characters the ICU provider happened to fold and the libc one did
-- not, and U+200B / U+2060 / U+180E are invisible but are not White_Space and
-- are not U+FEFF. Folding any of them here would merge two buckets the
-- clients keep apart, which is the same defect pointing the other way.
select is(
  (select count(*)::int
     from unnest(array[28, 29, 30, 31, 6158, 8203, 8288]) as cp
    where public.normalise_exercise_name('Bench' || chr(cp) || 'Press')
          <> 'bench' || chr(cp) || 'press'),
  0,
  'the code points outside the class are preserved, not folded'
);

select * from finish();
rollback;
