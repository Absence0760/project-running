-- Pin the plan_weeks / plan_workouts write split from migration
-- 20260613_001_rls_hardening.sql.
--
-- Pre-fix: 20260524_001_plan_templates.sql relaxed both child tables to
-- `for all using (EXISTS ...)`. The intent was "club members can SELECT
-- the workouts of a club template they share". The side effect: members
-- could ALSO INSERT / UPDATE / DELETE the workouts of any club template
-- they could see. Write authority on `training_plans` was correctly
-- gated to admins or owners; that authority did not flow to the children.
--
-- Fix: split each `for all` into a relaxed SELECT (parent visible →
-- children visible) and a tightened INSERT/UPDATE/DELETE that
-- re-asserts the parent's write rule (owner OR club admin).
--
-- Coverage:
--   1. Non-admin club member can SELECT the workouts of an admin's
--      club template (read flow preserved).
--   2. Non-admin club member CANNOT INSERT a plan_workout into the
--      admin's template (the regression).
--   3. Non-admin club member CANNOT UPDATE a plan_workout on the
--      admin's template (same regression, UPDATE side).
--   4. Non-admin club member CANNOT DELETE a plan_workout on the
--      admin's template (same regression, DELETE side).
--   5. Owner of a personal training_plan can INSERT plan_weeks +
--      plan_workouts on their own plan (positive control).
--   6. Club admin CAN INSERT plan_workouts on a club template they
--      own (positive control — admin write authority is preserved).

begin;

select plan(6);

-- Two users: an admin who publishes a club template, and a non-admin
-- club member who can see it but should not be able to write.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ff01', 'authenticated', 'authenticated',
   'admin@plan-write.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ff02', 'authenticated', 'authenticated',
   'member@plan-write.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('44444444-4444-4444-4444-444444444401',
        '00000000-0000-0000-0000-00000000ff01',
        'Plan Write Test Club', 'plan-write-test', true);

-- enroll_club_owner_trigger has already created the owner row; only
-- seed the member.
insert into club_members (club_id, user_id, role, status)
values
  ('44444444-4444-4444-4444-444444444401',
   '00000000-0000-0000-0000-00000000ff02', 'member', 'active');

-- Admin's club template + a week + a workout.
insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week,
  status, is_template, club_id
) values (
  '88888888-8888-8888-8888-888888888801',
  '00000000-0000-0000-0000-00000000ff01',
  'Club Template', 'distance_full', 42195, 14400,
  '2026-06-01', '2026-08-31', 5,
  'completed', true, '44444444-4444-4444-4444-444444444401'
);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values
  ('88888888-8888-8888-8888-888888888802',
   '88888888-8888-8888-8888-888888888801', 0, 'base', 30000);

insert into plan_workouts (
  id, week_id, kind, scheduled_date, target_distance_m, target_pace_sec_per_km
) values (
  '88888888-8888-8888-8888-888888888803',
  '88888888-8888-8888-8888-888888888802',
  'easy', '2026-06-01', 8000, 360
);

-- ── Switch to the non-admin member ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ff02","role":"authenticated"}';

-- 1. Non-admin member can SELECT the admin's workout (read preserved).
select results_eq(
  $$ select count(*)::int from plan_workouts
     where id = '88888888-8888-8888-8888-888888888803' $$,
  $$ values (1) $$,
  'non-admin club member can SELECT plan_workouts of an admin club template'
);

-- 2. Non-admin member CANNOT INSERT a new workout into the admin's
--    template — RLS WITH CHECK on insert returns zero affected rows
--    (Postgres raises 42501).
select throws_ok(
  $$ insert into plan_workouts (week_id, kind, scheduled_date, target_distance_m)
     values ('88888888-8888-8888-8888-888888888802', 'easy',
             '2026-06-08', 5000) $$,
  '42501',
  null,
  'non-admin member cannot INSERT plan_workouts into admin club template (the regression fix)'
);

-- 3. Non-admin member's UPDATE on the admin's workout is silently
--    no-op'd (UPDATE policy USING returns no rows for them).
do $$
declare
  v_affected integer;
begin
  update plan_workouts
     set target_distance_m = 9999
   where id = '88888888-8888-8888-8888-888888888803';
  get diagnostics v_affected = row_count;
  if v_affected <> 0 then
    raise exception 'plan_workouts_no_cross_member_update: expected 0, got %', v_affected;
  end if;
end $$;
select pass('non-admin member cannot UPDATE plan_workouts on admin club template');

-- 4. Non-admin member's DELETE on the admin's workout is silently
--    no-op'd.
do $$
declare
  v_affected integer;
begin
  delete from plan_workouts
   where id = '88888888-8888-8888-8888-888888888803';
  get diagnostics v_affected = row_count;
  if v_affected <> 0 then
    raise exception 'plan_workouts_no_cross_member_delete: expected 0, got %', v_affected;
  end if;
end $$;
select pass('non-admin member cannot DELETE plan_workouts on admin club template');

-- 5. Positive control: a member writing on THEIR OWN personal plan
--    works end-to-end (week + workout).
do $$
declare
  v_plan_id uuid;
  v_week_id uuid;
begin
  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, start_date, end_date,
    days_per_week, status
  ) values (
    '00000000-0000-0000-0000-00000000ff02',
    'Personal plan', 'distance_5k', 5000,
    '2026-09-01', '2026-09-28', 4, 'active'
  ) returning id into v_plan_id;
  insert into plan_weeks (plan_id, week_index, phase, target_volume_m)
  values (v_plan_id, 0, 'base', 20000)
  returning id into v_week_id;
  insert into plan_workouts (week_id, kind, scheduled_date, target_distance_m)
  values (v_week_id, 'tempo', '2026-09-01', 6000);
end $$;
select pass('owner of a personal plan can INSERT plan_weeks + plan_workouts on their own plan');

-- ── Switch to the admin and confirm they CAN write to their template ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ff01","role":"authenticated"}';

-- 6. Club admin CAN INSERT a workout into the club template they own
--    (positive control — admin write authority is preserved).
do $$
begin
  insert into plan_workouts (
    week_id, kind, scheduled_date, target_distance_m
  ) values (
    '88888888-8888-8888-8888-888888888802', 'long', '2026-06-15', 16000
  );
end $$;
select pass('club admin can INSERT plan_workouts into a club template they own');

select * from finish();

rollback;
