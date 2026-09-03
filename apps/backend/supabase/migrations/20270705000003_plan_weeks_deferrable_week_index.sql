-- `plan_weeks.week_index` could not be bounded while a shipped RPC parked rows
-- at negative indices to renumber them.
--
-- Found by the sweep behind 20270705000001/2/4: of the 79 numeric columns in
-- `public` carrying no CHECK, this is the one whose bound was not merely
-- unwritten but UNSTATABLE. `duplicate_plan_week` inserts a copy of a week and
-- shifts every later week up one, and the `(plan_id, week_index)` unique
-- constraint is checked per row, so a single `week_index = week_index + 1`
-- collides with the row it is about to vacate. The function worked around that
-- by hopping the tail through NEGATIVE index space and back:
--
--     update plan_weeks set week_index = -(week_index + 1) where week_index > p;
--     update plan_weeks set week_index = -week_index      where week_index < 0;
--
-- Correct, atomic, and invisible to any reader — but it means a week index is
-- legitimately negative for the span of two statements, so `check (week_index
-- >= 0)` fails a shipped surface rather than a bad write. Adding the CHECK
-- without this migration turns the plan editor's "duplicate week" button into a
-- 23514; `duplicate_plan_week_test.sql` is what caught it.
--
-- ── Why deferral rather than a positive scratch offset ─────────────────────
-- Hopping through `week_index + 1 + offset` instead would have kept the
-- constraint statable with a three-line change and no schema move. It was not
-- taken: the scratch hop exists ONLY because the uniqueness is checked per row,
-- and Postgres's answer to that is a deferrable constraint, not a second
-- coordinate space. `plan_weeks_plan_id_week_index_key` becomes DEFERRABLE
-- INITIALLY IMMEDIATE — so every other writer on the table is unaffected and
-- still gets its 23505 at the statement — and the function defers it for the
-- span of the renumber, then sets it back to IMMEDIATE, which forces the check
-- there rather than at COMMIT. A duplicate therefore still raises inside the
-- RPC, and the offset arithmetic (plus its smallint overflow question at
-- 16,383 weeks) stops existing.
--
-- ── Online safety (docs/backend/migration_locks.md) ────────────────────────
-- Changing a unique constraint's deferrability requires dropping and re-adding
-- it, which rebuilds the backing index under ACCESS EXCLUSIVE. There is no
-- NOT VALID form for that and `create index concurrently` cannot run inside a
-- migration's transaction. It is acceptable here and only here: `plan_weeks`
-- is one row per plan-week, it is not in the playbook's high-volume set, and
-- the playbook's own rule is that ceremony on a small bounded table is not
-- required. Do not read this as a precedent for `runs` or either ping table.
--
-- Ordering matters: this lands BEFORE 20270705000004 adds
-- `plan_weeks_week_index_check`, so there is no window in which the CHECK
-- exists and the function still writes negatives.
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table plan_weeks
  drop constraint plan_weeks_plan_id_week_index_key,
  add constraint plan_weeks_plan_id_week_index_key
    unique (plan_id, week_index) deferrable initially immediate;

CREATE OR REPLACE FUNCTION public.duplicate_plan_week(p_plan_id uuid, p_week_index integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Make room at p_week_index + 1 by bumping every later week up one. The
  -- unique constraint is checked per row, so a single statement transiently
  -- collides; it is DEFERRABLE INITIALLY IMMEDIATE as of this migration and is
  -- deferred for the span of the renumber, then set back to immediate so a
  -- duplicate raises HERE rather than at COMMIT. This replaces a hop through
  -- negative index space, which worked but made `week_index >= 0` unstatable.
  set constraints plan_weeks_plan_id_week_index_key deferred;
  update plan_weeks set week_index = week_index + 1
    where plan_id = p_plan_id and week_index > p_week_index;
  set constraints plan_weeks_plan_id_week_index_key immediate;

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
$function$;
