-- A plan row a DIFFERENT user owns never carries the source owner's private
-- fields, and `assign_plan_to_athlete` was the one head-inserting routine that
-- did not honour that.
--
-- Three routines insert a `training_plans` head from another plan.
-- `clone_plan_template` and `clone_public_plan` both write literal `null, null`
-- into `vdot` / `current_5k_seconds` under the comment "publisher-private
-- fitness data -- never propagated to the clone", and 20270508_001 backs that
-- with `private.strip_template_private_fields`, a BEFORE INSERT OR UPDATE
-- trigger that nulls `vdot`, `current_5k_seconds` AND `notes` on any
-- `is_template` row. `assign_plan_to_athlete` writes `src.vdot`,
-- `src.current_5k_seconds` and `src.notes` -- and its source is typically the
-- coach's own PERSONAL plan, which is not a template and therefore does carry
-- all three.
--
-- ── Which reading is right, and why the prescription one does not hold ──────
-- The prescription reading is that the plan's paces are the coach's
-- prescription and the VDOT they were derived from is part of it. It fails on
-- three counts. The prescription itself is `plan_workouts` and it is carried in
-- full (20270517_001 + 20270710000003). `plan.vdot` is rendered as a bare
-- header stat -- "VDOT 52.3" on /plans, /plans/[id], PlanEditor,
-- plans_screen.dart and plan_detail_screen.dart -- with no attribution, so the
-- athlete reads the coach's number as a claim about themselves. And
-- `current_5k_seconds` is not a prescription under any reading: it is the
-- coach's own recent race time.
--
-- The privacy reading is the one the schema already states. 20270508_001
-- classified exactly these three columns as owner-only, and its reason applies
-- verbatim here: the row reaches a reader who is not the owner. The mechanism
-- differs -- there an RLS template branch, here an ownership transfer -- and the
-- disclosure is the same. `notes` was not in the filing and is the strongest of
-- the three: it is free text ("training constraints, injury history", per that
-- migration), it has no reader surface on the athlete's plan pages at all, and
-- the sanctioned prose channel for a plan given to someone else is `rules`,
-- which 20270710000003 added to all three paths for exactly that purpose and
-- which this migration leaves carried.
--
-- Nothing depends on the values arriving. Both clone paths already produce a
-- fully working plan with `vdot` and `current_5k_seconds` null, and the athlete
-- sets their own via /plans/new.
--
-- ── Why this is not a trigger, unlike the template case ────────────────────
-- 20270508_001 needed a trigger because a plain REST POST with
-- `{"is_template":true, "vdot":55.3}` was itself the leak -- the client-side
-- strip was going around. There is no such bypass here: the "users own their
-- plans" policy is `with check (auth.uid() = user_id ...)` (20270123_001), so a
-- client cannot insert a `training_plans` row owned by anybody else at all, and
-- this SECURITY DEFINER routine is the only path that creates one. A trigger
-- keyed on `assigned_by_coach_id is not null` would also be actively wrong: it
-- would fire on every later UPDATE of the assigned plan, and `updatePlanMeta`
-- lets the ATHLETE write `notes` on the plan they own -- so the belt-and-braces
-- would silently delete the athlete's own text forever.
--
-- ── No backfill ────────────────────────────────────────────────────────────
-- Deliberately none. Every already-assigned row is the athlete's own data now:
-- the notes may have been read, acted on or edited by them, and nulling a
-- column on a row somebody else owns to repair OUR disclosure is a second
-- unilateral write on their data. The disclosure that already happened is not
-- undone by deleting the evidence from the athlete's copy, and the coach's own
-- source row is untouched either way. This closes the path forward.
--
-- The body below is 20270710000003's applied definition with `src.vdot`,
-- `src.current_5k_seconds` and `src.notes` replaced by literal nulls and
-- nothing else changed, so it diffs verbatim against the previous one.
-- Pinned by assign_plan_to_athlete_test.sql.

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
    src.days_per_week,
    -- Source-owner-private: the coach's own fitness measurements and their own
    -- plan-level free text. The prescription is plan_workouts + rules, both
    -- carried below. Same three columns 20270508_001 strips from a template.
    null, null,
    'active', null, p_source_plan_id, false, caller,
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
