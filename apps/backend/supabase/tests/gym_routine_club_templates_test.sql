-- Pins migration 20270109_001 (gym-routine club templates). gym_programming.md.
--
-- publish_gym_routine_as_template (author + club-admin gated):
--   1. The author, who is an admin of the target club, publishes a personal
--      routine into a NEW club-owned routine; exercises + sets copy across,
--      target loads preserved.
--   2. Publishing to a club the caller does NOT administer is rejected.
--   3. A non-author is rejected.
-- RLS read boundary:
--   4. A club member can SELECT the club-owned template (+ its children).
--   5. A stranger cannot.
-- clone_gym_routine_template (author-or-member adopt into a personal copy):
--   6. A club member clones the template into a personal, club-less routine.
--   7. The copy carries the exercises + sets.
--   8. A non-member is rejected.
--   9. The author can clone their own routine.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000a001', 'authenticated', 'authenticated', 'author@grct.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a002', 'authenticated', 'authenticated', 'member@grct.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a003', 'authenticated', 'authenticated', 'stranger@grct.local', '', now(), now());

-- Club A owned by the author (the enroll trigger makes them an owner-admin);
-- the member joins. Club B is owned by the stranger — the author is neither
-- member nor admin of B.
insert into clubs (id, owner_id, name, slug)
values
  ('cccccccc-0000-0000-0000-00000000a001', '99999999-0000-0000-0000-00000000a001', 'GRCT A', 'grct-a'),
  ('cccccccc-0000-0000-0000-00000000a002', '99999999-0000-0000-0000-00000000a003', 'GRCT B', 'grct-b');

insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-00000000a001', '99999999-0000-0000-0000-00000000a002', 'member', 'active');

-- The author's personal routine: one exercise, two sets with a target load, so
-- the copy exercises the exercise + set paths and load preservation.
insert into gym_routines (id, author_id, title, exercise_count)
values ('aaaaaaaa-0000-0000-0000-00000000a001', '99999999-0000-0000-0000-00000000a001', 'GRCT 5x5', 1);

insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
values ('eeeeeeee-0000-0000-0000-00000000a001',
        'aaaaaaaa-0000-0000-0000-00000000a001', 'Back Squat', 'back squat', 0);

insert into gym_routine_sets (routine_exercise_id, set_index, target_reps_min, target_weight_kg)
values
  ('eeeeeeee-0000-0000-0000-00000000a001', 0, 5, 60.00),
  ('eeeeeeee-0000-0000-0000-00000000a001', 1, 5, 60.00);

set local role authenticated;

-- ============================================================
-- 1. the author (admin of club A) publishes into a club template
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}';
select lives_ok(
  $$select publish_gym_routine_as_template('aaaaaaaa-0000-0000-0000-00000000a001',
                                           'cccccccc-0000-0000-0000-00000000a001')$$,
  'the author + club admin can publish a routine as a club template'
);

select is(
  (select count(*)::int from gym_routines
     where club_id = 'cccccccc-0000-0000-0000-00000000a001'
       and author_id = '99999999-0000-0000-0000-00000000a001' and title = 'GRCT 5x5'),
  1, 'publish makes exactly one club-owned routine');

select is(
  (select count(*)::int from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.club_id = 'cccccccc-0000-0000-0000-00000000a001'),
  2, 'the published template carries both sets');

select is(
  (select max(s.target_weight_kg) from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.club_id = 'cccccccc-0000-0000-0000-00000000a001'),
  60.00, 'target load is preserved on the published set');

-- ============================================================
-- 2. publishing to a club the caller does not administer is rejected
-- ============================================================
select throws_ok(
  $$select publish_gym_routine_as_template('aaaaaaaa-0000-0000-0000-00000000a001',
                                           'cccccccc-0000-0000-0000-00000000a002')$$,
  'P0001',
  'publish_gym_routine_as_template: not a club admin of cccccccc-0000-0000-0000-00000000a002',
  'cannot publish into a club you do not administer'
);

-- ============================================================
-- 3. a non-author cannot publish the routine
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a002","role":"authenticated"}';
select throws_ok(
  $$select publish_gym_routine_as_template('aaaaaaaa-0000-0000-0000-00000000a001',
                                           'cccccccc-0000-0000-0000-00000000a001')$$,
  'P0001',
  'publish_gym_routine_as_template: only the author may publish routine aaaaaaaa-0000-0000-0000-00000000a001',
  'a non-author cannot publish the routine'
);

-- ============================================================
-- 4 + 5. RLS read boundary on the club-owned template
-- ============================================================
-- The member sees the club template (and its sets through the inherited read).
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a002","role":"authenticated"}';
select is(
  (select count(*)::int from gym_routines where club_id = 'cccccccc-0000-0000-0000-00000000a001'),
  1, 'a club member can read the club-owned template');
select is(
  (select count(*)::int from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.club_id = 'cccccccc-0000-0000-0000-00000000a001'),
  2, 'a club member can read the template sets through the inherited policy');

-- The stranger (not a member of club A) sees nothing.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a003","role":"authenticated"}';
select is(
  (select count(*)::int from gym_routines where club_id = 'cccccccc-0000-0000-0000-00000000a001'),
  0, 'a non-member cannot read the club-owned template');

-- ============================================================
-- 6 + 7. a club member adopts (clones) the template
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a002","role":"authenticated"}';
select lives_ok(
  $$select clone_gym_routine_template(
      (select id from gym_routines where club_id = 'cccccccc-0000-0000-0000-00000000a001'))$$,
  'a club member can clone the club template');

select is(
  (select count(*)::int from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
     join gym_routines r on r.id = e.routine_id
     where r.author_id = '99999999-0000-0000-0000-00000000a002'
       and r.club_id is null and r.title = 'GRCT 5x5'),
  2, 'the adopted copy is personal (club_id null) and carries both sets');

-- ============================================================
-- 8. a non-member cannot clone the club template
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a003","role":"authenticated"}';
select throws_ok(
  $$select clone_gym_routine_template(
      (select id from gym_routines where club_id = 'cccccccc-0000-0000-0000-00000000a001'))$$,
  'P0001', null,
  'a non-member of the owning club cannot clone the template');

-- ============================================================
-- 9. the author can clone their own (personal) routine
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}';
select lives_ok(
  $$select clone_gym_routine_template('aaaaaaaa-0000-0000-0000-00000000a001')$$,
  'the author can clone their own routine');

select finish();
rollback;
