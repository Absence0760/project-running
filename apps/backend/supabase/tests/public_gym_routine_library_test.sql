-- Pins migration 20270224_001 (public gym-routine library). gym_programming.md.
--
-- set_gym_routine_public (owner publish / unpublish toggle):
--   1. The author publishes their personal routine (flips is_public_template).
--   2. A non-author cannot publish it.
--   3. A club-owned routine cannot be made a public template.
-- RLS public read boundary:
--   4. A stranger (no club tie) can SELECT the public template + its children.
--   5. A stranger cannot SELECT a private (non-public, non-club) routine.
-- clone_gym_routine_template (public-template adopt):
--   6. A stranger clones the public template into a personal, club-less copy.
--   7. The copy carries the exercises + sets, target load preserved, NOT public.
--   8. After the author unpublishes, the stranger can no longer clone it.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000ab01'::uuid, 'authenticated', 'authenticated', 'author@pgrl.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000ab02'::uuid, 'authenticated', 'authenticated', 'stranger@pgrl.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000ab03'::uuid, 'authenticated', 'authenticated', 'clubadmin@pgrl.local', '', now(), now());

-- A club owned by the third user, with one club-owned routine (to exercise the
-- not-club-owned publish guard).
insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-00000000ab01'::uuid, '99999999-0000-0000-0000-00000000ab03'::uuid, 'PGRL Club', 'pgrl-club');

insert into gym_routines (id, author_id, club_id, title, exercise_count)
values ('cccccccc-0000-0000-0000-0000000000c1'::uuid, '99999999-0000-0000-0000-00000000ab03'::uuid,
        'cccccccc-0000-0000-0000-00000000ab01'::uuid, 'PGRL Club Routine', 0);

-- The author's personal routine: one exercise, two sets with a target load.
insert into gym_routines (id, author_id, title, exercise_count)
values ('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid, '99999999-0000-0000-0000-00000000ab01'::uuid, 'PGRL 5x5', 1);

insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
values ('eeeeeeee-0000-0000-0000-00000000ab01'::uuid,
        'aaaaaaaa-0000-0000-0000-00000000ab01'::uuid, 'Back Squat', 'back squat', 0);

insert into gym_routine_sets (routine_exercise_id, set_index, target_reps_min, target_weight_kg)
values
  ('eeeeeeee-0000-0000-0000-00000000ab01'::uuid, 0, 5, 70.00),
  ('eeeeeeee-0000-0000-0000-00000000ab01'::uuid, 1, 5, 70.00);

set local role authenticated;

-- ============================================================
-- 1. the author publishes their personal routine
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab01","role":"authenticated"}';
select lives_ok(
  $$select set_gym_routine_public('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid, true)$$,
  'the author can publish their personal routine to the public library'
);

select is(
  (select is_public_template from gym_routines where id = 'aaaaaaaa-0000-0000-0000-00000000ab01'::uuid),
  true, 'the routine is now a public template');

-- ============================================================
-- 2. a non-author cannot publish the routine
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab02","role":"authenticated"}';
select throws_ok(
  $$select set_gym_routine_public('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid, false)$$,
  'P0001',
  'set_gym_routine_public: only the author may publish routine aaaaaaaa-0000-0000-0000-00000000ab01',
  'a non-author cannot publish / unpublish the routine'
);

-- ============================================================
-- 3. a club-owned routine cannot become a public template
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab03","role":"authenticated"}';
select throws_ok(
  $$select set_gym_routine_public('cccccccc-0000-0000-0000-0000000000c1'::uuid, true)$$,
  'P0001',
  'set_gym_routine_public: a club-owned routine cannot be a public template',
  'a club-owned routine cannot be made a public template'
);

-- ============================================================
-- 4 + 5. RLS public read boundary
-- ============================================================
-- The stranger sees the public template + its sets through the inherited reads.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab02","role":"authenticated"}';
select is(
  (select count(*)::int from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.id = 'aaaaaaaa-0000-0000-0000-00000000ab01'::uuid),
  2, 'a stranger can read a public template''s sets (preview)');

-- The stranger cannot read the club-owned routine (not a member, not public).
select is(
  (select count(*)::int from gym_routines where id = 'cccccccc-0000-0000-0000-0000000000c1'::uuid),
  0, 'a stranger cannot read a private (non-public, club-owned) routine');

-- ============================================================
-- 6 + 7. a stranger adopts (clones) the public template
-- ============================================================
select lives_ok(
  $$select clone_gym_routine_template('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid)$$,
  'a stranger can clone a public template');

select results_eq(
  $$select count(*)::int, max(s.target_weight_kg), bool_or(r.is_public_template)
     from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.author_id = '99999999-0000-0000-0000-00000000ab02'::uuid
       and r.club_id is null and r.title = 'PGRL 5x5'$$,
  $$values (2, 70.00::numeric(7,2), false)$$,
  'the clone is personal (club-less), NOT public, and carries both sets with load preserved');

-- ============================================================
-- 8. after the author unpublishes, the stranger can no longer clone
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab01","role":"authenticated"}';
select set_gym_routine_public('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid, false);

set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000ab02","role":"authenticated"}';
select throws_ok(
  $$select clone_gym_routine_template('aaaaaaaa-0000-0000-0000-00000000ab01'::uuid)$$,
  'P0001', null,
  'after unpublish, a stranger can no longer clone the routine');

select finish();
rollback;
