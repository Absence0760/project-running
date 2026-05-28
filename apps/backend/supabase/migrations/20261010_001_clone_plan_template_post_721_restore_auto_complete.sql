-- Re-apply the auto-complete-active-plan logic to clone_plan_template
-- that 20260721_001_plan_templates_strip_fitness.sql unwittingly stripped
-- when it did a `create or replace function` to null-out the publisher's
-- vdot / current_5k_seconds during clone.
--
-- The Round 2 commit 20260529000004 added an UPDATE
--   update training_plans set status = 'completed'
--   where user_id = caller and status = 'active' and is_template = false
-- before inserting the new clone, so the partial unique index
-- `training_plans_one_active` wouldn't trip when a runner adopts a club
-- template while an existing plan is in progress. The 20260721 rewrite
-- (legitimate privacy fix — strips publisher's vdot/current_5k_seconds
-- from the clone) bare-bodied the function and lost that UPDATE.
--
-- This consolidation rolls both together so every Adopt path (web wizard,
-- mobile Templates tab, future SDK callers) gets the auto-complete AND
-- the fitness-strip. Pinned by clone_plan_template_auto_complete_test.

create or replace function clone_plan_template(
  template_id uuid,
  new_start_date date
) returns uuid
language plpgsql
security definer
set search_path = public
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
        target_pace_sec_per_km, target_pace_tolerance_sec, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.structure, workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;
