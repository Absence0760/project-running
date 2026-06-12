-- Coach plan assignment (training.md Deferred -> shipped; personas #46/#47).
--
-- 20261102_001 established the coach-athlete link (status='active' == the
-- athlete's consent, formed when they redeem the coach's invite token).
-- 20261116_001 let an active coach READ all three plan tables and UPDATE an
-- athlete's plan_workouts. The remaining gap: a coach could tweak an athlete's
-- existing workouts but had no way to give them a whole plan in the first place.
--
-- This migration closes it with:
--   1. training_plans.assigned_by_coach_id -- provenance (who assigned it).
--   2. assign_plan_to_athlete(source_plan, athlete, start_date) -- a
--      SECURITY DEFINER deep-clone (mirroring clone_plan_template, 20260524_001)
--      that writes an ATHLETE-OWNED active plan from one of the coach's own
--      plans/templates (or a club template they can read).
--
-- Clone-not-subscribe (decisions §35): later edits to the coach's source plan
-- do NOT propagate. The athlete OWNS the result -- it flows through the
-- unchanged "users own their plans" RLS, the client-side auto-match, and every
-- activities/plan surface exactly like a self-created plan, and the athlete can
-- edit/abandon/delete it. The coach retains the read + plan_workouts-edit access
-- granted by 20261116_001 so they can keep tuning it.
--
-- Consent + safety:
--   * Gated on private.is_active_coach_of(caller, athlete) -- same helper the
--     read/edit policies use. Ending the link blocks future assignments but
--     leaves already-assigned plans with the athlete (it is their data now).
--   * The caller must be able to READ the source plan: their own plan/template,
--     or a club template they're a member of -- the same gate clone_plan_template
--     enforces. A coach cannot launder an unreadable plan into an athlete.
--   * Raises if the athlete already has an active plan -- never silently abandon
--     an athlete's own plan; the coach coordinates with them first.

-- ─────────────────────── Provenance column ───────────────────────
-- Nullable, no default -> metadata-only add on PG11+ (no table rewrite). The FK
-- to auth.users only validates non-null values, of which there are none on the
-- existing rows, so the add is safe on the populated prod table. ON DELETE SET
-- NULL: if the coach's account is erased, the athlete keeps the plan, provenance
-- simply clears (the plan is the athlete's own data, not the coach's).
alter table training_plans
  add column assigned_by_coach_id uuid references auth.users(id) on delete set null;

create index training_plans_assigned_by_coach
  on training_plans (assigned_by_coach_id)
  where assigned_by_coach_id is not null;

-- ─────────────────────── assign_plan_to_athlete RPC ───────────────────────
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

grant execute on function assign_plan_to_athlete(uuid, uuid, date) to authenticated;
