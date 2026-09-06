-- Every plan-clone path carries the whole plan.
--
-- `20270517_001` found that `clone_plan_template` and `assign_plan_to_athlete`
-- copied nine of `plan_workouts`' eleven prescription columns and dropped
-- `pace_zone` and `target_pace_end_sec_per_km` -- a coach's 300 -> 270 s/km
-- progression in zone T reached the athlete as a flat 5:00/km with no zone.
-- It fixed the two paths it named. `clone_public_plan` (20270126_001) is the
-- third, was never named, and still drops both: a runner cloning a plan out of
-- the public library gets the paces flattened exactly as the athlete did.
-- `plan_clone_pace_columns_test.sql` stayed green throughout, because it
-- exercises the two RPCs its own migration touched.
--
-- Measured rather than assumed: `pg_proc.prosrc ~* 'insert into plan_workouts'`
-- returns exactly four routines -- the three clone paths and
-- `duplicate_plan_week`, which already carries all eleven.
--
-- ── and two columns ALL THREE heads drop ───────────────────────────────────
-- The same query over `training_plans` returns three routines, and none of
-- them copies `source` or `rules` (20260420_001):
--
--   * `source` is the attribution ('generated' / 'imported' / 'manual') the
--     editor reads to decide whether regenerating a plan would destroy
--     hand-authored structure. A clone of a plan pasted in from a coach's
--     document is still that document's plan; landing it on the `generated`
--     default tells the editor it is safe to regenerate over the top.
--   * `rules` is the plan-wide prose the publisher wrote ("80% easy", "cut
--     climbing from phase 2") and the plan hero renders. It is part of the
--     plan a runner chose, and it vanished on every clone and every coach
--     assignment.
--
-- Both are copied from the source row by all three now. Neither is
-- publisher-private the way `vdot` / `current_5k_seconds` are -- those stay
-- nulled on the two paths that null them (20260721_001), and this migration
-- does not touch that.
--
-- The three bodies below are the applied definitions with those columns added
-- and nothing else changed; they were taken from `pg_get_functiondef` and
-- patched, so a reviewer can diff them against the previous definitions
-- verbatim.


-- ─────────────────── clone_public_plan ───────────────────

CREATE OR REPLACE FUNCTION public.clone_public_plan(template_id uuid, new_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'clone_public_plan: not authenticated';
  end if;

  -- Anti-bulk-clone rate limit — same shape as clone_plan_template
  -- (20 clones / hour / caller). A caller with the public library list
  -- cannot loop-clone every public template UUID into their account.
  perform enforce_create_rate_limit('clone_public_plan', caller, 20, 3600);

  -- DEFINER context bypasses RLS, so this reads any public template
  -- regardless of caller. The is_public_template gate is the access check.
  select * into tmpl
  from training_plans
  where id = template_id
    and is_template = true
    and is_public_template = true;

  if not found then
    raise exception 'clone_public_plan: public template not found';
  end if;

  -- Auto-complete the caller's existing active plan so the insert below
  -- doesn't trip the training_plans_one_active partial unique index and
  -- surface as a raw 23505 to the client (mirrors clone_plan_template).
  update training_plans
  set status = 'completed', updated_at = now()
  where user_id = caller
    and status = 'active'
    and is_template = false;

  date_offset_days := new_start_date - tmpl.start_date;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, is_public_template,
    source, rules
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false, false,
    tmpl.source, tmpl.rules
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
        target_pace_sec_per_km, target_pace_end_sec_per_km,
        target_pace_tolerance_sec, pace_zone, structure, notes
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
$function$;

-- ─────────────────── clone_plan_template ───────────────────

CREATE OR REPLACE FUNCTION public.clone_plan_template(template_id uuid, new_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
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
    status, notes, parent_template_id, is_template, source, rules
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone
    -- (migration 20260721_001).
    null, null,
    'active', tmpl.notes, template_id, false, tmpl.source, tmpl.rules
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
$function$;

-- ─────────────────── assign_plan_to_athlete ───────────────────

CREATE OR REPLACE FUNCTION public.assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    status, notes, parent_template_id, is_template, assigned_by_coach_id,
    source, rules
  )
  values (
    p_athlete_id, src.name, src.goal_event, src.goal_distance_m, src.goal_time_seconds,
    p_start_date, src.end_date + date_offset_days,
    src.days_per_week, src.vdot, src.current_5k_seconds,
    'active', src.notes, p_source_plan_id, false, caller,
    src.source, src.rules
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
$function$;
