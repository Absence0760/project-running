-- Pins migration 20270222_001 (exercise catalogue: exercises +
-- gym_sets.exercise_id). The contract:
--
--   1. Every authenticated user reads the seeded global catalogue
--      (author_id is null) AND their own custom entries (author_id = uid).
--   2. A user can INSERT/UPDATE/DELETE only their OWN custom entries; they
--      cannot mutate a seeded global, cannot create a row owned by someone
--      else, and cannot read another user's customs.
--   3. gym_sets.exercise_id is a NULLABLE link; deleting a custom catalogue
--      entry SETs NULL on the logged set (history immutable, set reverts to
--      free-text), and removing the owner's auth.users row cascades the
--      custom exercise away.
begin;
select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('88888888-0000-0000-0000-00000000e001', 'authenticated', 'authenticated', 'owner@ex.local', '', now(), now()),
  ('88888888-0000-0000-0000-00000000e002', 'authenticated', 'authenticated', 'stranger@ex.local', '', now(), now());

-- A seeded global already exists from the migration; capture one for the read
-- assertions. Seed one custom entry for the owner (superuser, RLS bypassed).
insert into exercises (id, author_id, name, name_key, category, modality)
values ('88888888-0000-0000-0000-0000000eaa01', '88888888-0000-0000-0000-00000000e001', 'My Cable Curl', 'my cable curl', 'arms', 'weight_reps');

-- A logged gym workout + set that references the owner's custom exercise, to
-- prove on-delete-set-null preserves the logged set.
insert into gym_workouts (id, user_id, started_at)
values ('88888888-0000-0000-0000-0000000e0c01', '88888888-0000-0000-0000-00000000e001', now());
insert into gym_sets (id, workout_id, set_index, exercise_name, exercise_id, reps, weight_kg)
values ('88888888-0000-0000-0000-0000000e5e71', '88888888-0000-0000-0000-0000000e0c01', 0, 'My Cable Curl', '88888888-0000-0000-0000-0000000eaa01', 10, 20);

set local role authenticated;

-- ============================================================
-- Owner: reads globals + own custom; writes own custom
-- ============================================================
set local "request.jwt.claims" = '{"sub":"88888888-0000-0000-0000-00000000e001","role":"authenticated"}';

select cmp_ok(
  (select count(*)::int from exercises where author_id is null),
  '>=', 40, 'owner reads the seeded global catalogue (>= 40 rows)');

select is(
  (select count(*)::int from exercises where author_id = '88888888-0000-0000-0000-00000000e001'),
  1, 'owner reads their own custom entry');

select lives_ok(
  $$ insert into exercises (author_id, name, name_key) values ('88888888-0000-0000-0000-00000000e001', 'My Hack Squat', 'my hack squat') $$,
  'owner inserts their own custom entry');

select throws_ok(
  $$ insert into exercises (author_id, name, name_key) values (null, 'Forged Global', 'forged global') $$,
  '42501',
  null,
  'owner cannot create a seeded-global (author_id null) row');

-- A logged set may reference NO catalogue entry (free-text path stays valid).
select lives_ok(
  $$ insert into gym_sets (workout_id, set_index, exercise_name, reps)
     values ('88888888-0000-0000-0000-0000000e0c01', 1, 'Freehand Plank', 12) $$,
  'a logged set with exercise_id null (free-text) still inserts');

-- ============================================================
-- Stranger: reads globals, NOT the owner's customs; cannot forge
-- ============================================================
set local "request.jwt.claims" = '{"sub":"88888888-0000-0000-0000-00000000e002","role":"authenticated"}';

select cmp_ok(
  (select count(*)::int from exercises where author_id is null),
  '>=', 40, 'a stranger ALSO reads the shared seeded global catalogue');

select is(
  (select count(*)::int from exercises where author_id = '88888888-0000-0000-0000-00000000e001'),
  0, 'a stranger cannot read another user''s custom entries');

select throws_ok(
  $$ insert into exercises (author_id, name, name_key) values ('88888888-0000-0000-0000-00000000e001', 'Forged', 'forged') $$,
  '42501',
  null,
  'a stranger cannot create a custom entry owned by someone else');

-- A stranger's update against a seeded global is RLS-filtered to zero rows.
select lives_ok(
  $$ update exercises set name = 'hijacked' where author_id is null $$,
  'a stranger''s update of a global runs but is RLS-filtered to zero rows');
select is(
  (select count(*)::int from exercises where name = 'hijacked'),
  0, 'no seeded global was mutated by the stranger')
  from (select set_config('request.jwt.claims', '{"sub":"88888888-0000-0000-0000-00000000e001","role":"authenticated"}', true)) _;

-- ============================================================
-- on-delete-set-null: deleting a custom entry keeps the logged set
-- ============================================================
reset role;
delete from exercises where id = '88888888-0000-0000-0000-0000000eaa01';
select is(
  (select exercise_id from gym_sets where id = '88888888-0000-0000-0000-0000000e5e71'),
  null, 'deleting a custom exercise SETs NULL on the logged set (history preserved)');

-- ============================================================
-- cascade-delete on auth.users removal (DSAR erasure)
-- ============================================================
delete from auth.users where id = '88888888-0000-0000-0000-00000000e001';
select is(
  (select count(*)::int from exercises where author_id = '88888888-0000-0000-0000-00000000e001'),
  0, 'deleting the auth user cascade-removes their custom catalogue entries');

select * from finish();
rollback;
