-- Two plan-clone RPCs silently dropped `pace_zone` and
-- `target_pace_end_sec_per_km` when copying `plan_workouts`.
--
-- Both columns have existed since 20260420_001. `duplicate_plan_week` and
-- the web client's own copy path carry all eleven workout columns; these two
-- carried nine. So three of the five copy paths were right and two were wrong,
-- with nothing to make the difference visible.
--
-- The effect is that a coach's prescription is flattened on the way to the
-- athlete. A progression long run written as 300 -> 270 s/km in zone 'T'
-- arrives as a flat 5:00/km with no zone: the pace-range UI has nothing to
-- render, and the workout the athlete executes is not the one that was
-- written. Same for every club template adopted through `clone_plan_template`.
--
-- Per the "bare CREATE OR REPLACE strips prior fixes" gotcha, each body below
-- is the LATEST live definition re-emitted verbatim with ONLY the two columns
-- added to its INSERT:
--   clone_plan_template    <- 20261010_001 (auto-complete active plan +
--                             publisher fitness-strip + anti-bulk-clone limit),
--                             carrying 20261120_001's `search_path = public,
--                             private` — that was applied as an ALTER, not a
--                             redefinition, so re-emitting the original
--                             `set search_path = public` silently reverts it
--                             and the body's private.is_club_member call
--                             stops resolving.
--   assign_plan_to_athlete <- 20270106_001 (coach plan assignment)
--
-- Pinned by plan_clone_pace_columns_test.sql.

create or replace function clone_plan_template(
  template_id uuid,
  new_start_date date
) returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  new_plan_id uuid;
  new_week_id uuid;
  date_offset_days int;
  week_record record;
  workout_record record;
begin
  if caller is null then
    raise exception 'clone_plan_template: not authenticated';
  end if;

  -- Anti-bulk-clone rate limit (migration 20260927_001). 20 clones per
  -- hour per caller — same shape as create_route. A club member with
  -- the public-template list cannot loop-clone every public template
  -- UUID and bulk-create rows under their account.
  perform enforce_create_rate_limit('clone_plan_template', caller, 20, 3600);

  select * into tmpl
  from training_plans
  where id = template_id and is_template = true;

  if not found then
    raise exception 'clone_plan_template: template not found';
  end if;

  if tmpl.user_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_plan_template: not authorised to clone template %', template_id;
  end if;

  -- Auto-complete the caller's existing active plan (Round 2 finding
  -- Intermediate #1) so the insert below doesn't trip the partial
  -- unique index `training_plans_one_active` and surface as a raw
  -- 23505 to the client.
  update training_plans
  set status = 'completed', updated_at = now()
  where user_id = caller
    and status = 'active'
    and is_template = false;

  date_offset_days := new_start_date - tmpl.start_date;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone
    -- (migration 20260721_001).
    null, null,
    'active', tmpl.notes, template_id, false
  )
  returning id into new_plan_id;

  for week_record in
    select * from plan_weeks where plan_id = template_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
        pace_zone, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure, workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

create or replace function assign_plan_to_athlete(
  p_source_plan_id uuid,
  p_athlete_id     uuid,
  p_start_date     date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller           uuid := auth.uid();
  src              training_plans%rowtype;
  date_offset_days int;
  new_plan_id      uuid;
  week_record      record;
  workout_record   record;
  new_week_id      uuid;
begin
  if caller is null then
    raise exception 'assign_plan_to_athlete: not authenticated';
  end if;

  if caller = p_athlete_id then
    raise exception 'assign_plan_to_athlete: cannot assign a plan to yourself';
  end if;

  -- Consent gate: the active coach_athletes link is the athlete's consent.
  if not private.is_active_coach_of(caller, p_athlete_id) then
    raise exception 'assign_plan_to_athlete: not an active coach of athlete %', p_athlete_id;
  end if;

  -- Source must exist and be readable by the caller (own plan/template, or a
  -- club template they're a member of) -- mirrors clone_plan_template's gate.
  select * into src from training_plans where id = p_source_plan_id;
  if not found then
    raise exception 'assign_plan_to_athlete: source plan % not found', p_source_plan_id;
  end if;
  if src.user_id <> caller
     and not (src.is_template = true and src.club_id is not null and private.is_club_member(src.club_id))
  then
    raise exception 'assign_plan_to_athlete: not authorised to use source plan %', p_source_plan_id;
  end if;

  -- Never silently clobber the athlete's own active plan.
  if exists (
    select 1 from training_plans
    where user_id = p_athlete_id and status = 'active'
  ) then
    raise exception 'assign_plan_to_athlete: athlete already has an active plan';
  end if;

  date_offset_days := p_start_date - src.start_date;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, assigned_by_coach_id
  )
  values (
    p_athlete_id, src.name, src.goal_event, src.goal_distance_m, src.goal_time_seconds,
    p_start_date, src.end_date + date_offset_days,
    src.days_per_week, src.vdot, src.current_5k_seconds,
    'active', src.notes, p_source_plan_id, false, caller
  )
  returning id into new_plan_id;

  -- Date-shift weeks → workouts by the same offset (mirrors clone_plan_template).
  for week_record in
    select * from plan_weeks where plan_id = p_source_plan_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
        pace_zone, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind,
        workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure,
        workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

