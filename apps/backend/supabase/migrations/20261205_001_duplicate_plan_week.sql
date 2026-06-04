-- Duplicate-a-week bulk op (decisions.md training-moat follow-on).
--
-- Repeating a week (extend a base block, add a recovery week, copy a
-- heavy interval week) was deferred on the client because it can't be
-- done safely with per-row updates: `plan_weeks` carries a
-- `unique (plan_id, week_index)` constraint, so shifting every later
-- week up by one to make room for the copy transiently collides, and a
-- partial failure mid-shift leaves a plan with a duplicate or a hole in
-- its week numbering. This RPC does the whole thing in one transaction.
--
-- Semantics: duplicate the week at `p_week_index`, inserting the copy
-- immediately after it as the new `p_week_index + 1`. Every later week
-- shifts up by one index and its workouts move back by 7 days; the
-- copied week's workouts land 7 days after their source. The plan's
-- end_date extends by 7 days (start_date is unchanged). Completion
-- state (completed_run_id / completed_at / manually_completed) is NOT
-- copied — a freshly-inserted future week starts un-done.
--
-- SECURITY DEFINER so the multi-statement re-index runs without each
-- write re-evaluating RLS, but the caller must own the plan (structural
-- edits stay with the owner even for club-shared templates, mirroring
-- the existing owner-only bulk ops on /plans/[id]).

create or replace function duplicate_plan_week(
  p_plan_id uuid,
  p_week_index int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller        uuid := auth.uid();
  v_plan        training_plans%rowtype;
  v_src         plan_weeks%rowtype;
  v_new_week_id uuid;
  workout_record record;
begin
  if caller is null then
    raise exception 'duplicate_plan_week: not authenticated';
  end if;

  select * into v_plan from training_plans where id = p_plan_id;
  if not found then
    raise exception 'duplicate_plan_week: plan % not found', p_plan_id;
  end if;

  -- Owner-only. Club members can read a template's weeks but only the
  -- owner restructures it.
  if v_plan.user_id <> caller then
    raise exception 'duplicate_plan_week: not authorised to edit plan %', p_plan_id;
  end if;

  select * into v_src from plan_weeks
    where plan_id = p_plan_id and week_index = p_week_index;
  if not found then
    raise exception 'duplicate_plan_week: week % not found in plan %',
      p_week_index, p_plan_id;
  end if;

  -- Push the workouts of every later week back by 7 days. Done BEFORE
  -- the re-index (while the tail is still the only thing past
  -- p_week_index) and BEFORE the copy exists, so the new week's
  -- workouts aren't caught by this shift.
  update plan_workouts
    set scheduled_date = scheduled_date + 7
    where week_id in (
      select id from plan_weeks
      where plan_id = p_plan_id and week_index > p_week_index
    );

  -- Make room at p_week_index + 1 by bumping every later week up one.
  -- A single `set week_index = week_index + 1` would transiently
  -- violate the (plan_id, week_index) unique index because the per-row
  -- check fires before the statement settles; hop through negative
  -- index space, which never collides with the remaining positive rows.
  update plan_weeks set week_index = -(week_index + 1)
    where plan_id = p_plan_id and week_index > p_week_index;
  update plan_weeks set week_index = -week_index
    where plan_id = p_plan_id and week_index < 0;

  insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (p_plan_id, p_week_index + 1, v_src.phase, v_src.target_volume_m, v_src.notes)
    returning id into v_new_week_id;

  for workout_record in
    select * from plan_workouts where week_id = v_src.id
  loop
    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
      target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
      pace_zone, structure, notes
    )
    values (
      v_new_week_id,
      workout_record.scheduled_date + 7,
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

  update training_plans
    set end_date = end_date + 7, updated_at = now()
    where id = p_plan_id;

  return v_new_week_id;
end;
$$;

grant execute on function duplicate_plan_week(uuid, int) to authenticated;
