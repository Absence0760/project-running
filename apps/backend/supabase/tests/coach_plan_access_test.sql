-- pgtap suite for coach plan access (20261116_001).
--
-- An active coach (coach_athletes.status='active') can READ an athlete's
-- training plan (training_plans/plan_weeks/plan_workouts) and EDIT existing
-- plan_workouts. A stranger cannot; an ended link revokes both.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
   'coach@plan.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated',
   'athlete@plan.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000d3', 'authenticated', 'authenticated',
   'stranger@plan.local', '', now(), now());

-- Coach→athlete link, active. Seeded as superuser (before any set role) so
-- the fixture isn't subject to coach_athletes RLS.
insert into coach_athletes (coach_id, athlete_id, status, invite_token)
values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'active', 'tok-coach-plan-access-test');

-- Athlete owns a (non-template) plan with one week + one workout.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000a2"}';
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date)
values ('aaaaaaaa-0000-0000-0000-00000000dd01',
   '00000000-0000-0000-0000-0000000000a2', 'Marathon Build', 'distance_full', 42195,
   current_date, current_date + 84);
insert into plan_weeks (id, plan_id, week_index, phase)
values ('aaaaaaaa-0000-0000-0000-00000000ee01',
   'aaaaaaaa-0000-0000-0000-00000000dd01', 0, 'base');
insert into plan_workouts (id, week_id, scheduled_date, kind, target_pace_sec_per_km, notes)
values ('aaaaaaaa-0000-0000-0000-00000000ff01',
   'aaaaaaaa-0000-0000-0000-00000000ee01', current_date, 'easy', 360, 'easy 8k');

-- 1. Coach reads the athlete's plan workout.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000c1"}';
select is(
  (select count(*)::int from plan_workouts
     where id = 'aaaaaaaa-0000-0000-0000-00000000ff01'),
  1,
  'active coach can read the athlete plan workout'
);

-- 2. Coach can also read the parent plan + week (transitive read).
select is(
  (select count(*)::int from training_plans
     where id = 'aaaaaaaa-0000-0000-0000-00000000dd01')
  + (select count(*)::int from plan_weeks
     where id = 'aaaaaaaa-0000-0000-0000-00000000ee01'),
  2,
  'active coach can read the parent plan + week'
);

-- 3. Coach edits the workout (RLS UPDATE allowed → value changes; coach
--    reads it back through the coach SELECT policy).
update plan_workouts set target_pace_sec_per_km = 330
 where id = 'aaaaaaaa-0000-0000-0000-00000000ff01';
select is(
  (select target_pace_sec_per_km from plan_workouts
     where id = 'aaaaaaaa-0000-0000-0000-00000000ff01'),
  330,
  'active coach can edit (update) the athlete plan workout'
);

-- 4. Stranger (no link) cannot read it.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000d3"}';
select is(
  (select count(*)::int from plan_workouts
     where id = 'aaaaaaaa-0000-0000-0000-00000000ff01'),
  0,
  'a non-coach stranger cannot read the athlete plan workout'
);

-- 5. Stranger cannot edit it (RLS hides the row → no change). Verify via a
--    privileged read that the value is still the coach's 330.
update plan_workouts set target_pace_sec_per_km = 999
 where id = 'aaaaaaaa-0000-0000-0000-00000000ff01';
set local role postgres;
select is(
  (select target_pace_sec_per_km from plan_workouts
     where id = 'aaaaaaaa-0000-0000-0000-00000000ff01'),
  330,
  'a non-coach stranger cannot edit the athlete plan workout'
);
set local role authenticated;

-- 6. Ending the link revokes the coach's read immediately.
set local role postgres;
update coach_athletes set status = 'ended'
 where coach_id = '00000000-0000-0000-0000-0000000000c1'
   and athlete_id = '00000000-0000-0000-0000-0000000000a2';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000c1"}';
select is(
  (select count(*)::int from plan_workouts
     where id = 'aaaaaaaa-0000-0000-0000-00000000ff01'),
  0,
  'ended coach link revokes plan read'
);

select * from finish();
rollback;
