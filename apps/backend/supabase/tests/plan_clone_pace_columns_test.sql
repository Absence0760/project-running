-- Pins that both plan-clone RPCs carry the FULL prescription (20270517_001).
--
-- `clone_plan_template` and `assign_plan_to_athlete` each copied nine of
-- `plan_workouts`' eleven prescription columns, silently dropping `pace_zone`
-- and `target_pace_end_sec_per_km`. A coach's progression run written as
-- 300 -> 270 s/km in zone 'T' reached the athlete as a flat 5:00/km with no
-- zone — the workout executed was not the workout written.
--
-- Asserted as "no prescription column is null after the copy" rather than
-- naming only the two that were broken, so a column added to plan_workouts
-- and forgotten in a clone path fails here too.

begin;
select plan(8);

do $$
declare
  v_coach   uuid := '99999999-9999-9999-9999-9999ace00001';
  v_athlete uuid := '99999999-9999-9999-9999-9999ace00002';
  v_tmpl    uuid := gen_random_uuid();
  v_twk     uuid := gen_random_uuid();
  v_src     uuid := gen_random_uuid();
  v_swk     uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values
      (v_coach, 'paceclone-coach@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
      (v_athlete, 'paceclone-athlete@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_coach, 'Pace Coach', 'km', 'free'),
           (v_athlete, 'Pace Athlete', 'km', 'free')
    on conflict (id) do nothing;

  -- A public template owned by the coach, carrying a progression workout:
  -- a pace RANGE (300 -> 270) inside a named zone.
  insert into training_plans (
    id, user_id, name, goal_event, goal_distance_m,
    start_date, end_date, days_per_week, status, is_template
  ) values (
    v_tmpl, v_coach, 'Pace template', 'distance_10k', 10000,
    date '2026-07-06', date '2026-07-19', 4, 'completed', true
  );
  insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
    values (v_twk, v_tmpl, 0, 'build', 40000);
  insert into plan_workouts (
    week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
    target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
    pace_zone, structure, notes
  ) values (
    v_twk, date '2026-07-08', 'tempo', 12000, 3600,
    300, 270, 8, 'T', '{"steady": {"distance_m": 8000}}'::jsonb, 'progression'
  );

  -- The same shape as a non-template source plan the coach will assign.
  insert into training_plans (
    id, user_id, name, goal_event, goal_distance_m,
    start_date, end_date, days_per_week, status, is_template
  ) values (
    v_src, v_coach, 'Assignable plan', 'distance_10k', 10000,
    date '2026-07-06', date '2026-07-19', 4, 'completed', false
  );
  insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
    values (v_swk, v_src, 0, 'build', 40000);
  insert into plan_workouts (
    week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
    target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
    pace_zone, structure, notes
  ) values (
    v_swk, date '2026-07-08', 'tempo', 12000, 3600,
    300, 270, 8, 'T', '{"steady": {"distance_m": 8000}}'::jsonb, 'progression'
  );

  -- Link the coach to the athlete so assign_plan_to_athlete is authorised.
  insert into coach_athletes (coach_id, athlete_id, status, accepted_at, invite_token)
    values (v_coach, v_athlete, 'active', now(), gen_random_uuid()::text)
    on conflict do nothing;
end $$;

-- ── clone_plan_template (the Adopt path) ──────────────────────────────────
-- Cloned by the template's owner: the authorisation branch is owner-or-club-
-- member, and which branch let the caller in has no bearing on which columns
-- the copy carries.
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999ace00001","role":"authenticated"}';
set local role = 'authenticated';

do $$
declare v_new uuid;
begin
  select clone_plan_template(
    (select id from training_plans where name = 'Pace template'),
    date '2026-08-03'
  ) into v_new;
  create temp table _cloned as
    select w.* from plan_workouts w
    join plan_weeks k on k.id = w.week_id
    where k.plan_id = v_new;
end $$;

select is((select count(*)::int from _cloned), 1,
  'clone_plan_template copies the workout');
select is((select target_pace_sec_per_km from _cloned), 300,
  'clone_plan_template carries the pace range start');
select is((select target_pace_end_sec_per_km from _cloned), 270,
  'clone_plan_template carries target_pace_end_sec_per_km');
select is((select pace_zone from _cloned), 'T',
  'clone_plan_template carries pace_zone');

-- ── assign_plan_to_athlete (the coach roster path) ────────────────────────
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999ace00001","role":"authenticated"}';
set local role = 'authenticated';

do $$
declare v_new uuid;
begin
  select assign_plan_to_athlete(
    (select id from training_plans where name = 'Assignable plan'),
    '99999999-9999-9999-9999-9999ace00002'::uuid,
    date '2026-09-07'
  ) into v_new;
  create temp table _assigned as
    select w.* from plan_workouts w
    join plan_weeks k on k.id = w.week_id
    where k.plan_id = v_new;
end $$;

select is((select count(*)::int from _assigned), 1,
  'assign_plan_to_athlete copies the workout');
select is((select target_pace_sec_per_km from _assigned), 300,
  'assign_plan_to_athlete carries the pace range start');
select is((select target_pace_end_sec_per_km from _assigned), 270,
  'assign_plan_to_athlete carries target_pace_end_sec_per_km');
select is((select pace_zone from _assigned), 'T',
  'assign_plan_to_athlete carries pace_zone');

select * from finish();
rollback;
