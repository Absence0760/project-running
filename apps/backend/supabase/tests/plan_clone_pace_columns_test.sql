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
--
-- Extended by 20270710000003, which found the same file's own blind spot: it
-- exercises the two RPCs that migration touched, and `clone_public_plan` --
-- the third path, and the one an ordinary runner uses -- was still dropping
-- both columns two months later while this file stayed green. All three clone
-- paths are driven here now. `pg_proc.prosrc ~* 'insert into plan_workouts'`
-- returns exactly four routines; the fourth, `duplicate_plan_week`, already
-- carried all eleven and is not a clone path.
--
-- The plan HEAD is asserted too, on all three. `source` (the attribution the
-- editor reads before regenerating over hand-authored structure) and `rules`
-- (the plan-wide prose the hero renders) were dropped by every one of them, so
-- the fixture writes non-default values -- 'imported' rather than the
-- 'generated' column default, and a two-entry rules array -- and a path that
-- drops either lands on the default rather than on the publisher's value.

begin;
select plan(19);

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
  -- The publisher's own fitness is written here deliberately, and the
  -- assertion at the bottom of this file is that it does not survive. See the
  -- comment there for why it is asserted at the template and not at the clone.
  update training_plans
     set is_public_template = true,
         source = 'imported',
         rules = '["80% easy", "sleep 8h"]'::jsonb,
         vdot = 50,
         current_5k_seconds = 1200
   where id = v_tmpl;
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
  update training_plans
     set source = 'imported',
         rules = '["80% easy", "sleep 8h"]'::jsonb
   where id = v_src;
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
  create temp table _cloned_head as
    select * from training_plans where id = v_new;
end $$;

select is((select count(*)::int from _cloned), 1,
  'clone_plan_template copies the workout');
select is((select target_pace_sec_per_km from _cloned), 300,
  'clone_plan_template carries the pace range start');
select is((select target_pace_end_sec_per_km from _cloned), 270,
  'clone_plan_template carries target_pace_end_sec_per_km');
select is((select pace_zone from _cloned), 'T',
  'clone_plan_template carries pace_zone');
select is((select source from _cloned_head), 'imported',
  'clone_plan_template carries the plan''s source attribution');
select is((select rules from _cloned_head), '["80% easy", "sleep 8h"]'::jsonb,
  'clone_plan_template carries the plan-wide rules');

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
  create temp table _assigned_head as
    select * from training_plans where id = v_new;
end $$;

select is((select count(*)::int from _assigned), 1,
  'assign_plan_to_athlete copies the workout');
select is((select target_pace_sec_per_km from _assigned), 300,
  'assign_plan_to_athlete carries the pace range start');
select is((select target_pace_end_sec_per_km from _assigned), 270,
  'assign_plan_to_athlete carries target_pace_end_sec_per_km');
select is((select pace_zone from _assigned), 'T',
  'assign_plan_to_athlete carries pace_zone');
select is((select source from _assigned_head), 'imported',
  'assign_plan_to_athlete carries the plan''s source attribution');
select is((select rules from _assigned_head), '["80% easy", "sleep 8h"]'::jsonb,
  'assign_plan_to_athlete carries the plan-wide rules');

-- ── clone_public_plan (the public-library path) ───────────────────────────
-- The path 20270517_001 did not name. A runner adopting a plan out of the
-- public library went through this one, and it flattened the progression the
-- other two were fixed to carry.
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999ace00001","role":"authenticated"}';
set local role = 'authenticated';

do $$
declare v_new uuid;
begin
  select clone_public_plan(
    (select id from training_plans where name = 'Pace template' and is_template),
    date '2026-10-05'
  ) into v_new;
  create temp table _public as
    select w.* from plan_workouts w
    join plan_weeks k on k.id = w.week_id
    where k.plan_id = v_new;
  create temp table _public_head as
    select * from training_plans where id = v_new;
end $$;

select is((select count(*)::int from _public), 1,
  'clone_public_plan copies the workout');
select is((select target_pace_sec_per_km from _public), 300,
  'clone_public_plan carries the pace range start');
select is((select target_pace_end_sec_per_km from _public), 270,
  'clone_public_plan carries target_pace_end_sec_per_km');
select is((select pace_zone from _public), 'T',
  'clone_public_plan carries pace_zone');
select is((select source from _public_head), 'imported',
  'clone_public_plan carries the plan''s source attribution');
select is((select rules from _public_head), '["80% easy", "sleep 8h"]'::jsonb,
  'clone_public_plan carries the plan-wide rules');

-- The publisher-private fitness columns are not propagated (20260721_001), and
-- copying `source` and `rules` is not a licence to start. Asserted at the
-- TEMPLATE rather than at the clone, because the clone is the layer that
-- cannot fail: `private.strip_template_private_fields` is a BEFORE INSERT OR
-- UPDATE trigger that nulls `vdot` / `current_5k_seconds` on any row with
-- `is_template`, so a public template cannot HOLD the publisher's fitness and
-- `clone_public_plan`'s own `null, null` has nothing to copy either way.
-- Measured: with the assertion pointed at the clone, a mutation making it copy
-- `tmpl.vdot` and `tmpl.current_5k_seconds` survived the whole file -- the
-- fixture's UPDATE above had already been stripped, so both readings were
-- null. The redundancy is deliberate (20260721_001 § (a)); the assertion
-- belongs on the half that enforces it.
select is(
  (select coalesce(vdot::text, 'null') || '/' || coalesce(current_5k_seconds::text, 'null')
     from training_plans where name = 'Pace template' and is_template),
  'null/null',
  'a public template cannot hold the publisher''s own fitness, so no clone path can carry it');

select * from finish();
rollback;
