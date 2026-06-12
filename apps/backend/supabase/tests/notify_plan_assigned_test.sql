-- pgtap for the plan-assigned notification trigger (20270107_001).
--
-- Inserting a training_plans row with assigned_by_coach_id set notifies the
-- owner (athlete); a self-assigned or un-assigned plan notifies nobody.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@notif.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'athlete@notif.local', '', now(), now());

-- 1+2. A coach-assigned plan creates exactly one plan_assigned notification for
--      the athlete, stamped with the coach as actor + the plan as source.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, assigned_by_coach_id)
values ('aaaaaaaa-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
        'Assigned Plan', 'distance_10k', 10000, current_date, current_date + 56,
        '00000000-0000-0000-0000-0000000000c1');

select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000000a2'
       and kind = 'plan_assigned'
       and actor_id = '00000000-0000-0000-0000-0000000000c1'
       and plan_id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  1,
  'assigning a plan notifies the athlete (actor=coach, plan_id=the plan)'
);
select is(
  (select count(*)::int from notifications where plan_id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  1,
  'exactly one notification per assignment'
);

-- 3. A self-assigned plan (assigned_by_coach_id = owner) notifies nobody.
--    status='completed' so it doesn't collide with a2's one active plan above.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, status, assigned_by_coach_id)
values ('aaaaaaaa-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a2',
        'Self Plan', 'distance_5k', 5000, current_date, current_date + 42, 'completed',
        '00000000-0000-0000-0000-0000000000a2');
select is(
  (select count(*)::int from notifications where plan_id = 'aaaaaaaa-0000-0000-0000-0000000000a3'),
  0,
  'a self-assigned plan notifies nobody'
);

-- 4. A normal (un-assigned) plan notifies nobody.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, status)
values ('aaaaaaaa-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000a2',
        'Own Plan', 'distance_5k', 5000, current_date, current_date + 42, 'completed');
select is(
  (select count(*)::int from notifications where plan_id = 'aaaaaaaa-0000-0000-0000-0000000000a4'),
  0,
  'a self-created plan with no coach notifies nobody'
);

select * from finish();
rollback;
