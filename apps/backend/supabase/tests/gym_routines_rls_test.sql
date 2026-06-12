-- Pins migration 20261231_001 (gym programming P1: gym_routines +
-- gym_routine_exercises + gym_routine_sets). The contract:
--
--   1. gym_routines is author-only for SELECT/INSERT/UPDATE/DELETE — there is
--      NO public-read branch in v1 (unlike gym_workouts). A stranger sees and
--      writes nothing.
--   2. gym_routine_exercises + gym_routine_sets have no owner column of their
--      own — visibility/writes are gated via EXISTS against the parent
--      routine's author_id (the "visible via parent" idiom gym_sets uses). A
--      stranger sees none of another author's exercises or sets.
--   3. The whole tree cascade-deletes when the author's auth.users row is
--      removed (DSAR erasure path), and deleting a routine cascades to its
--      exercises + sets.
begin;
select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000a001', 'authenticated', 'authenticated', 'author@gr.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a002', 'authenticated', 'authenticated', 'stranger@gr.local', '', now(), now());

-- Seed a routine tree for the author (superuser, RLS bypassed).
insert into gym_routines (id, author_id, title, exercise_count)
values ('99999999-0000-0000-0000-00000000aa01', '99999999-0000-0000-0000-00000000a001', 'Push day', 1);

insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
values ('99999999-0000-0000-0000-00000000bb01', '99999999-0000-0000-0000-00000000aa01', 'Bench Press', 'bench press', 0);

insert into gym_routine_sets (id, routine_exercise_id, set_index, target_reps_min, target_weight_kg)
values ('99999999-0000-0000-0000-00000000cc01', '99999999-0000-0000-0000-00000000bb01', 0, 5, 80);

set local role authenticated;

-- ============================================================
-- gym_routines: author-only
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}';

select is(
  (select count(*)::int from gym_routines where author_id = '99999999-0000-0000-0000-00000000a001'),
  1, 'author reads their own routine');

select lives_ok(
  $$ insert into gym_routines (author_id, title) values ('99999999-0000-0000-0000-00000000a001', 'Pull day') $$,
  'author inserts their own routine');

-- The author sees their exercises + sets through the parent EXISTS gate.
select is(
  (select count(*)::int from gym_routine_exercises where routine_id = '99999999-0000-0000-0000-00000000aa01'),
  1, 'author reads their routine''s exercises via the parent gate');
select is(
  (select count(*)::int from gym_routine_sets where routine_exercise_id = '99999999-0000-0000-0000-00000000bb01'),
  1, 'author reads their routine''s planned sets via the parent gate');

-- ============================================================
-- Stranger sees / writes nothing
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a002","role":"authenticated"}';

select is(
  (select count(*)::int from gym_routines where author_id = '99999999-0000-0000-0000-00000000a001'),
  0, 'a stranger cannot read another author''s routines');
select is(
  (select count(*)::int from gym_routine_exercises where routine_id = '99999999-0000-0000-0000-00000000aa01'),
  0, 'a stranger cannot read another author''s routine exercises');
select is(
  (select count(*)::int from gym_routine_sets where routine_exercise_id = '99999999-0000-0000-0000-00000000bb01'),
  0, 'a stranger cannot read another author''s routine sets');

select throws_ok(
  $$ insert into gym_routines (author_id, title) values ('99999999-0000-0000-0000-00000000a001', 'Forged') $$,
  '42501',
  null,
  'a stranger cannot insert a routine owned by someone else');

select throws_ok(
  $$ insert into gym_routine_exercises (routine_id, exercise_name, exercise_key, position)
     values ('99999999-0000-0000-0000-00000000aa01', 'Forged', 'forged', 1) $$,
  '42501',
  null,
  'a stranger cannot add an exercise to another author''s routine (parent gate)');

-- A stranger's delete against the author's routine is RLS-filtered to zero.
select lives_ok(
  $$ delete from gym_routines where id = '99999999-0000-0000-0000-00000000aa01' $$,
  'a stranger''s delete runs but is RLS-filtered');
select is(
  (select count(*)::int from gym_routines where id = '99999999-0000-0000-0000-00000000aa01'),
  1, 'the author''s routine survived the stranger''s delete (row invisible)')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}', true)) _;

-- ============================================================
-- cascade-delete on auth.users removal (DSAR erasure) — the whole tree
-- ============================================================
reset role;
delete from auth.users where id = '99999999-0000-0000-0000-00000000a001';
select is(
  (select count(*)::int
     from gym_routines r
     left join gym_routine_exercises e on e.routine_id = r.id
     left join gym_routine_sets s on s.routine_exercise_id = e.id
    where r.author_id = '99999999-0000-0000-0000-00000000a001'
       or e.id = '99999999-0000-0000-0000-00000000bb01'
       or s.id = '99999999-0000-0000-0000-00000000cc01'),
  0, 'deleting the auth user cascade-removes the routine + its exercises + sets');

select * from finish();
rollback;
