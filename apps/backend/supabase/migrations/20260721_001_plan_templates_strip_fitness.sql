-- Strip publisher fitness data from `training_plans` rows that are
-- shared as club templates.
--
-- Audit pass 3 finding: `publishPlanAsTemplate` (web data.ts) and
-- `clone_plan_template` (RPC, migration 20260524_001) both copy the
-- source plan's `vdot` and `current_5k_seconds` verbatim. These are
-- the publisher's personal fitness measurements, not template-design
-- values. Once on a template row with `club_id` set, every club
-- member's `fetchClubTemplates` SELECT returns them — leaking the
-- publisher's recent 5 km time and Daniels VDOT score to the whole
-- club.
--
-- Two layers of fix:
--   1. The web publisher already nulls these on insert (`data.ts`
--      change in this commit).
--   2. The clone RPC drops them when copying template → personal
--      plan. Note that this is purely defence-in-depth — the
--      template rows themselves shouldn't carry the values after
--      step (1). The clone-side strip exists because (a) any
--      pre-existing template rows from before this migration still
--      carry the publisher's values, and (b) a future writer that
--      bypasses `data.ts` shouldn't be able to leak.
--
-- Plus: backfill — any existing template rows have their `vdot` and
-- `current_5k_seconds` zeroed.

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

  -- SECURITY DEFINER context bypasses RLS on training_plans, so the
  -- select * into below reads any matching template row regardless
  -- of caller. The explicit authorisation check below is the
  -- single access gate.
  select * into tmpl
  from training_plans
  where id = template_id and is_template = true;

  if not found then
    raise exception 'clone_plan_template: template not found';
  end if;

  -- Caller must own the template OR be a club member of its club.
  if tmpl.user_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_plan_template: not authorised to clone template %', template_id;
  end if;

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
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner (`caller`) sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false
  )
  returning id into new_plan_id;

  -- Iterate weeks → workouts. Date-shift workouts by date_offset_days.
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
        workout_record.kind,
        workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.structure,
        workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

-- Backfill: any pre-existing template row carries the publisher's
-- fitness data; zero them.
update training_plans
   set vdot = null,
       current_5k_seconds = null
 where is_template = true
   and (vdot is not null or current_5k_seconds is not null);
