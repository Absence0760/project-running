-- pgtap suite for the exercise-name normalisation rail (migration
-- 20270623000001), the SQL half of decisions.md § 790.
--
-- `exercise_key` is a STORED grouping key and three rails derive it, so these
-- assertions are the SQL side of the pin `gym_prs.test.ts` and
-- `gym_prs_test.dart` carry. The fixture is deliberately NOT ASCII-only: the
-- previous cross-platform pin used `'bench  press'`, which every rail agreed
-- on, so it could not see the defect this migration fixes.
--
-- Covers:
--   * `btrim(text)` strips only U+0020 -- the reason every non-space edge
--     character used to survive the trim and become a leading/trailing SPACE
--   * every member of the shared whitespace class folds, inside and at both
--     edges, and the two non-members do not
--   * the five case folds no runtime agrees on, applied by hand
--   * no live gym function derives an exercise key any other way
--   * a tab-suffixed logged name is the SAME exercise as the clean one, both
--     to `gym_exercise_records` and to `gym_exercise_set_history`
--   * `gym_routine_exercises.exercise_key` is stamped by the server, whatever
--     key the client sent, and the CHECK holds

begin;

select plan(14);

-- 1. The defect at the root of it: btrim with no second argument is not a
--    whitespace trim, it is a SPACE trim. Pinned as a fact about postgres so a
--    future reader does not have to rediscover it the way § 790 did.
select is(
  btrim(chr(9) || 'x' || chr(9)),
  chr(9) || 'x' || chr(9),
  'btrim(text) strips only U+0020 -- a tab survives it untouched'
);

-- 2. Every member of the shared class folds from inside a name.
select is(
  (select count(*)::int
     from unnest(array[9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,
                       8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279]) as cp
    where normalise_exercise_name('Bench' || chr(cp) || 'Press') <> 'bench press'),
  0,
  'every class member folds to a single space inside a name'
);

-- 3. ... and from the LEADING edge, which is what btrim used to miss.
select is(
  (select count(*)::int
     from unnest(array[9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,
                       8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279]) as cp
    where normalise_exercise_name(chr(cp) || 'Bench Press') <> 'bench press'),
  0,
  'every class member is trimmed from the leading edge'
);

-- 4. ... and from the trailing edge.
select is(
  (select count(*)::int
     from unnest(array[9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,
                       8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279]) as cp
    where normalise_exercise_name('Bench Press' || chr(cp)) <> 'bench press'),
  0,
  'every class member is trimmed from the trailing edge'
);

-- 5. U+200B and U+180E are NOT whitespace on any rail. Widening the class in
--    SQL alone would re-key every stored name holding one.
select is(
  normalise_exercise_name('Bench' || chr(8203) || 'Press'),
  'bench' || chr(8203) || 'press',
  'a zero-width space is not folded'
);

-- 6. The case fold libc, JS and Dart disagree on. Postgres `lower()` is not
--    consulted for it, so the answer does not depend on the server's ctype.
select is(
  normalise_exercise_name(chr(304) || 'NCLINE PRESS'),
  'incline press',
  'U+0130 folds to a bare i, matching both clients'
);

-- 7. The four titlecase digraphs, the same shape one step rarer.
select is(
  normalise_exercise_name(chr(453) || chr(456) || chr(459) || chr(498)),
  chr(454) || chr(457) || chr(460) || chr(499),
  'the titlecase digraphs fold to their lowercase forms'
);

-- 8. Ordinary folding is still `lower()`, and a name that is all whitespace or
--    absent is the empty key both clients produce.
select is(
  array[normalise_exercise_name(chr(201) || 'l' || chr(233) || 'vation'),
        normalise_exercise_name(chr(9) || chr(10)),
        normalise_exercise_name(null)],
  array[chr(233) || 'l' || chr(233) || 'vation', '', ''],
  'ordinary case folding, an all-whitespace name and a null all behave'
);

-- 9. Nothing derives an exercise key any other way. Read off the LIVE bodies
--    rather than off the migration, because a later migration re-issuing an
--    older body is exactly how a single-sourced value comes unstuck (§ 787).
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'gym\_%'
      and pg_get_functiondef(p.oid) ilike '%exercise_name%'
      and pg_get_functiondef(p.oid) ilike '%regexp_replace%'),
  '',
  'no live gym function rolls its own exercise-name normalisation'
);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000b0001'::uuid, 'authenticated', 'authenticated',
        'lifter@normalise.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000b0001', 'Lifter');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';

insert into gym_workouts (id, user_id, title, started_at)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01',
   '00000000-0000-0000-0000-0000000b0001', 'Monday', now() - interval '2 days'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02',
   '00000000-0000-0000-0000-0000000b0001', 'Thursday', now() - interval '1 day');

-- The same lift, logged once cleanly and once with a pasted trailing tab and a
-- non-breaking space -- the two shapes a spreadsheet or a web page puts on a
-- name a lifter typed once.
insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 0, 'Bench Press', 5, 60),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 0, 'Bench' || chr(160) || 'Press' || chr(9), 5, 70);

-- 10. One exercise, not two. Under the old rule the tab-suffixed row keyed as
--     'bench press ' and the lifter's records page listed the same lift twice,
--     each with half their history.
select is(
  (select count(*)::int from gym_exercise_records()),
  1,
  'a tab-suffixed logged name is the same exercise, not a second one'
);

-- 11. ... and its all-time best comes from BOTH sessions.
select is(
  (select heaviest_weight_kg from gym_exercise_records()),
  70::numeric,
  'the heaviest set is found across both spellings'
);

-- 12. Asked for the clean spelling, the history RPC returns both sessions.
--     Under the old rule it returned one and the progression page showed a
--     lifter a single data point.
select is(
  (select count(*)::int from gym_exercise_set_history('Bench Press')),
  2,
  'set history asked by the clean name finds the tab-suffixed sets'
);

-- 13. The server stamps the persisted key, whatever the client sent. An
--     offline client with an older build can no longer write a key the server
--     disagrees with.
insert into gym_routines (id, author_id, title)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10',
        '00000000-0000-0000-0000-0000000b0001', 'Push');

insert into gym_routine_exercises (routine_id, exercise_name, exercise_key, position)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10',
        chr(9) || 'Bench Press', 'whatever the client sent', 0);

select is(
  (select exercise_key from gym_routine_exercises
    where routine_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10'),
  'bench press',
  'the trigger stamps the normalised key over whatever the client sent'
);

-- 14. ... including on a later rename, so the key cannot come unstuck from the
--     name it is derived from.
update gym_routine_exercises
   set exercise_name = 'Incline' || chr(160) || 'Press'
 where routine_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10';

select is(
  (select exercise_key from gym_routine_exercises
    where routine_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10'),
  'incline press',
  'renaming the exercise re-stamps the key'
);

select * from finish();
rollback;
