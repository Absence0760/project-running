-- Pins duplicate_plan_week (20261205_001): repeating a week inserts a
-- copy after it, re-indexes the tail without violating the
-- (plan_id, week_index) unique constraint, shifts later workouts +7d,
-- copies the source workouts +7d (without completion state), extends
-- the plan end_date, and rejects a non-owner caller.

begin;
select plan(10);

do $$
declare
  v_owner uuid := '99999999-9999-9999-9999-9999ddcc0001';
  v_other uuid := '99999999-9999-9999-9999-9999ddcc0002';
  v_plan  uuid := gen_random_uuid();
  v_w0    uuid := gen_random_uuid();
  v_w1    uuid := gen_random_uuid();
  v_w2    uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values
      (v_owner, 'dupweek-owner@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_other, 'dupweek-other@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_owner, 'Dup Owner', 'km', 'free'),
           (v_other, 'Dup Other', 'km', 'free')
    on conflict (id) do nothing;

  -- A 3-week plan starting on a fixed date so the +7-day assertions are
  -- exact. end_date sits one week past week 2.
  insert into training_plans (
    id, user_id, name, goal_event, goal_distance_m,
    start_date, end_date, days_per_week, status
  ) values (
    v_plan, v_owner, 'Dup plan', 'distance_10k', 10000,
    date '2026-07-06', date '2026-07-26', 4, 'active'
  );

  insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes)
    values
      (v_w0, v_plan, 0, 'base',  30000, 'wk0'),
      (v_w1, v_plan, 1, 'build', 40000, 'wk1'),
      (v_w2, v_plan, 2, 'build', 45000, 'wk2');

  -- One long run per week; week 1's is marked done (manually completed)
  -- so we can prove completion state is NOT carried into the copy.
  insert into plan_workouts (
    week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km,
    pace_zone, manually_completed, completed_at
  ) values
    (v_w0, date '2026-07-11', 'long', 12000, 360, 'E', false, null),
    (v_w1, date '2026-07-18', 'long', 16000, 355, 'E', true,  now()),
    (v_w2, date '2026-07-25', 'long', 18000, 350, 'E', false, null);

  perform set_config('t.owner', v_owner::text, true);
  perform set_config('t.other', v_other::text, true);
  perform set_config('t.plan',  v_plan::text, true);
  perform set_config('t.w1',    v_w1::text, true);
end $$;

-- ── Non-owner is rejected ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999ddcc0002","role":"authenticated"}';
set local role = 'authenticated';
select throws_ok(
  format('select duplicate_plan_week(%L, 1)', current_setting('t.plan', true)),
  'duplicate_plan_week: not authorised to edit plan ' || current_setting('t.plan', true),
  'A non-owner cannot duplicate a week in someone else''s plan'
);
reset role;

-- ── Owner duplicates week 1 ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999ddcc0001","role":"authenticated"}';
set local role = 'authenticated';
do $$
declare
  v_new uuid;
begin
  select duplicate_plan_week(current_setting('t.plan', true)::uuid, 1) into v_new;
  perform set_config('t.new_week', v_new::text, true);
end $$;
reset role;

-- 1. Plan now has 4 weeks.
select is(
  (select count(*) from plan_weeks where plan_id = current_setting('t.plan', true)::uuid),
  4::bigint,
  'Plan gains exactly one week'
);

-- 2. Week indices are still the dense 0..3 sequence (no hole, no dupe).
select is(
  (select array_agg(week_index order by week_index)
     from plan_weeks where plan_id = current_setting('t.plan', true)::uuid),
  array[0, 1, 2, 3]::smallint[],
  'Week indices are re-densified to 0..3'
);

-- 3. The copy landed at index 2, between the original week 1 and the
--    pushed-down former week 2.
select is(
  (select week_index from plan_weeks where id = current_setting('t.new_week', true)::uuid),
  2::smallint,
  'The duplicate is inserted as the new week index 2'
);

-- 4. The copy carries the source week's phase + volume + notes.
select results_eq(
  format($q$select phase::text, target_volume_m, notes from plan_weeks where id = %L$q$,
         current_setting('t.new_week', true)),
  $q$values ('build', 40000::numeric, 'wk1')$q$,
  'The copy mirrors the source week''s phase/volume/notes'
);

-- 5. The copy's workout is the source workout dated +7 days, with the
--    planned pace fields preserved.
select results_eq(
  format($q$select scheduled_date, kind::text, target_distance_m, target_pace_sec_per_km, pace_zone
              from plan_workouts where week_id = %L$q$,
         current_setting('t.new_week', true)),
  $q$values (date '2026-07-25', 'long', 16000::numeric, 355, 'E')$q$,
  'The copied workout is the source +7 days with pace fields intact'
);

-- 6. Completion state is dropped on the copy (source week 1 was done).
select is(
  (select manually_completed from plan_workouts
     where week_id = current_setting('t.new_week', true)::uuid),
  false,
  'The copy does not inherit the source''s completion flag'
);

-- 7. The former week 2 (now index 3) had its workout pushed back 7 days.
select is(
  (select scheduled_date from plan_workouts pw
     join plan_weeks w on w.id = pw.week_id
     where w.plan_id = current_setting('t.plan', true)::uuid and w.week_index = 3),
  date '2026-08-01',
  'The shifted-down week''s workout moves back by 7 days'
);

-- 8. The original week 1's own workout is untouched (still done, same date).
select is(
  (select scheduled_date from plan_workouts where week_id = current_setting('t.w1', true)::uuid),
  date '2026-07-18',
  'The source week''s own workout is unchanged'
);

-- 9. The plan end_date extended by 7 days.
select is(
  (select end_date from training_plans where id = current_setting('t.plan', true)::uuid),
  date '2026-08-02',
  'Plan end_date extends by one week'
);

select * from finish();
rollback;
