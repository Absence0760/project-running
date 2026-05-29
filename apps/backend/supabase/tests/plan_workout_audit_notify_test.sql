-- Pins migration 20261024_001 — plan-workout audit columns + the
-- 'plan_update' athlete notification (coach persona #48).
--
-- Asserts: (1) an owner edit stamps updated_by + updated_at and does NOT
-- self-notify; (2) a foreign-editor (coach) edit writes a 'plan_update'
-- notification to the plan owner with plan_id set. The coach edit is
-- simulated by setting the JWT claims to the coach while staying on the
-- superuser role (RLS bypassed — the coach-edit RLS path itself lands
-- with persona #46; this test pins the trigger behaviour underneath it).

begin;
select plan(6);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99990000a101', 'athlete-48@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99990000c202', 'coach-48@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date)
values ('aaaaaaaa-0000-0000-0000-000000004801',
        '99999999-9999-9999-9999-99990000a101',
        '10K build', 'distance_10k', 10000, '2026-06-01', '2026-07-27');

insert into plan_weeks (id, plan_id, week_index, phase)
values ('bbbbbbbb-0000-0000-0000-000000004801',
        'aaaaaaaa-0000-0000-0000-000000004801', 0, 'base');

insert into plan_workouts (id, week_id, scheduled_date, kind, notes)
values ('cccccccc-0000-0000-0000-000000004801',
        'bbbbbbbb-0000-0000-0000-000000004801', '2026-06-02', 'tempo', 'orig');

-- ── owner edits their own workout ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99990000a101","role":"authenticated"}';
update plan_workouts set notes = 'owner edit'
  where id = 'cccccccc-0000-0000-0000-000000004801';

select is(
  (select updated_by from plan_workouts where id = 'cccccccc-0000-0000-0000-000000004801'),
  '99999999-9999-9999-9999-99990000a101'::uuid,
  'owner edit stamps updated_by = owner');

select isnt(
  (select updated_at from plan_workouts where id = 'cccccccc-0000-0000-0000-000000004801'),
  null,
  'owner edit stamps updated_at');

select is(
  (select count(*)::int from notifications
   where kind = 'plan_update' and user_id = '99999999-9999-9999-9999-99990000a101'),
  0,
  'an owner editing their own plan does NOT notify themselves');

-- ── coach edits the athlete's workout ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99990000c202","role":"authenticated"}';
update plan_workouts set notes = 'coach edit'
  where id = 'cccccccc-0000-0000-0000-000000004801';

select is(
  (select updated_by from plan_workouts where id = 'cccccccc-0000-0000-0000-000000004801'),
  '99999999-9999-9999-9999-99990000c202'::uuid,
  'coach edit stamps updated_by = coach');

select is(
  (select count(*)::int from notifications
   where kind = 'plan_update'
     and user_id = '99999999-9999-9999-9999-99990000a101'
     and actor_id = '99999999-9999-9999-9999-99990000c202'),
  1,
  'a foreign-editor edit notifies the plan owner once');

select is(
  (select plan_id from notifications
   where kind = 'plan_update' and user_id = '99999999-9999-9999-9999-99990000a101'),
  'aaaaaaaa-0000-0000-0000-000000004801'::uuid,
  'the plan_update notification carries plan_id');

select * from finish();
rollback;
