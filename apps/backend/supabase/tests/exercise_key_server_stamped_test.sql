-- pgtap suite for the server-stamped exercise keys (migration 20270711000001).
--
-- `gym_routine_exercises.exercise_key` and `exercises.name_key` used to be
-- computed by the CLIENT and policed by a validated CHECK, so a client whose
-- frozen fold table predates the server's REFUSED a legitimate save with a
-- 23514 it could not act on (decisions § 830, § 1252). They are now derived by
-- a BEFORE INSERT OR UPDATE trigger, the shape `gym_sets.exercise_key` has
-- carried since 20270706000001, and the refusal becomes a silent correction.
--
-- The fixture uses the one case that is actually reachable in Latin text.
-- U+0130 (Turkish dotted capital I) is folded to a bare `i` by the frozen
-- table on all three rails, but a JS runtime's own `toLowerCase()` emits
-- `i` + U+0307 -- so `İncline Press` is exactly the name on which a stale web
-- build and the server disagree, and it is not synthetic: § 830 measured a
-- 23514 on a legitimate mobile save of `İtme`.
--
-- Everything runs inside the suite's own transaction and is rolled back.

begin;

select plan(11);

-- ── The CHECKs stay, and stay validated ─────────────────────────────────────

-- 1-2. The triggers make the two CHECKs unviolatable rather than redundant:
--      they are what turns a dropped or disabled trigger into a loud refusal
--      instead of a silently split history. A constraint added `not valid` and
--      never validated would make a claim about new rows only, which is also
--      what lets this suite skip a backfill -- every existing row is inside it.
select is(
  (select convalidated from pg_constraint
   where conrelid = 'public.gym_routine_exercises'::regclass
     and conname = 'gym_routine_exercises_exercise_key_canonical'),
  true,
  'gym_routine_exercises'' canonical CHECK is still validated'
);

select is(
  (select convalidated from pg_constraint
   where conrelid = 'public.exercises'::regclass
     and conname = 'exercises_name_key_canonical'),
  true,
  'exercises'' canonical CHECK is still validated'
);

-- ── Fixture ─────────────────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('77777777-0000-0000-0000-00000000f001', 'authenticated', 'authenticated',
        'lifter@stamped.local', '', now(), now());

insert into gym_routines (id, author_id, title)
values ('77777777-0000-0000-0000-0000000fa001',
        '77777777-0000-0000-0000-00000000f001', 'Stale client push day');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"77777777-0000-0000-0000-00000000f001","role":"authenticated"}';

-- ── gym_routine_exercises ───────────────────────────────────────────────────

-- 3-4. The headline: the key a stale build computes is REPLACED, not refused.
--    Before the trigger this insert raised 23514.
select lives_ok(
  $$ insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
     values ('77777777-0000-0000-0000-0000000fb001',
             '77777777-0000-0000-0000-0000000fa001',
             chr(304) || 'ncline Press',
             'i' || chr(775) || 'ncline press',
             0) $$,
  'a stale client''s exercise_key is accepted rather than refused'
);

select is(
  (select exercise_key from gym_routine_exercises
    where id = '77777777-0000-0000-0000-0000000fb001'),
  'incline press',
  'the stored key is the server''s fold, not the one the client sent'
);

-- 5. A client need not compute the key at all. The column is NOT NULL, so
--    without the constant default this insert would fail on the column rather
--    than reach the trigger -- and the generated Insert types would still
--    oblige every client to send it.
with ins as (
  insert into gym_routine_exercises (routine_id, exercise_name, position)
  values ('77777777-0000-0000-0000-0000000fa001', 'Front  Squat', 1)
  returning exercise_key
)
select is(
  (select exercise_key from ins),
  'front squat',
  'omitting exercise_key entirely stamps the canonical key'
);

-- 6. The trigger is unqualified for a reason: an UPDATE naming ONLY the key
--    would not fire an `update of exercise_name` trigger, and the CHECK would
--    then refuse it.
update gym_routine_exercises set exercise_key = 'moved elsewhere'
 where id = '77777777-0000-0000-0000-0000000fb001';

select is(
  (select exercise_key from gym_routine_exercises
    where id = '77777777-0000-0000-0000-0000000fb001'),
  'incline press',
  'an UPDATE that names only exercise_key is re-stamped, not refused'
);

-- 7. Renaming the exercise moves the key with it.
update gym_routine_exercises set exercise_name = 'Overhead   Press'
 where id = '77777777-0000-0000-0000-0000000fb001';

select is(
  (select exercise_key from gym_routine_exercises
    where id = '77777777-0000-0000-0000-0000000fb001'),
  'overhead press',
  'renaming the exercise re-derives the key from the new name'
);

-- ── exercises ───────────────────────────────────────────────────────────────

-- 8-9. Same headline on the catalogue. The two partial unique indexes are over
--    `name_key`, so a client-computed key was also deciding what counts as a
--    duplicate custom exercise.
select lives_ok(
  $$ insert into exercises (id, author_id, name, name_key)
     values ('77777777-0000-0000-0000-0000000fc001',
             '77777777-0000-0000-0000-00000000f001',
             chr(304) || 'ncline Fly',
             'i' || chr(775) || 'ncline fly') $$,
  'a stale client''s name_key is accepted rather than refused'
);

select is(
  (select name_key from exercises where id = '77777777-0000-0000-0000-0000000fc001'),
  'incline fly',
  'the stored catalogue key is the server''s fold'
);

-- 10. Omission works here too.
with ins as (
  insert into exercises (author_id, name)
  values ('77777777-0000-0000-0000-00000000f001', 'Cable  Crossover')
  returning name_key
)
select is(
  (select name_key from ins),
  'cable crossover',
  'omitting name_key entirely stamps the canonical key'
);

-- ── The mutation ────────────────────────────────────────────────────────────

-- 11. Every assertion above passes just as well against a client that happened
--    to send the right key. Take the trigger away and the same insert has to
--    raise the 23514 this migration exists to stop -- which proves the
--    correction is the trigger's doing, and that the CHECK behind it is still
--    live rather than decorative.
reset role;
alter table public.gym_routine_exercises
  disable trigger gym_routine_exercises_stamp_exercise_key_trigger;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"77777777-0000-0000-0000-00000000f001","role":"authenticated"}';

select throws_ok(
  $$ insert into gym_routine_exercises (routine_id, exercise_name, exercise_key, position)
     values ('77777777-0000-0000-0000-0000000fa001',
             chr(304) || 'ncline Press',
             'i' || chr(775) || 'ncline press',
             9) $$,
  '23514',
  null,
  'without the trigger the stale key is refused by the canonical CHECK'
);

select * from finish();
rollback;
