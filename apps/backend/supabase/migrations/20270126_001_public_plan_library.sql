-- Public plan library — anyone-can-clone (roadmap: "Public plan library").
--
-- The club-template mechanism (§35, migration 20260524_001) lets a club
-- admin publish a plan as an `is_template = true` row scoped to a
-- `club_id`, readable + cloneable only by that club's members via
-- `clone_plan_template`. This adds an orthogonal *public* library: a
-- publisher-owned template any authenticated user can preview + clone.
--
-- Shape decision: a public-library plan reuses the existing template
-- plumbing — it is `is_template = true` (so the `training_plans_one_active`
-- partial unique index, the `training_plans_template_status` CHECK, and the
-- weeks/workouts SELECT transitivity all keep working) with the new
-- `is_public_template = true` flag and `club_id = null` (publisher-owned,
-- not club-owned). This keeps club templates and public templates strictly
-- separable: a club template has `club_id` set and `is_public_template`
-- false; a public template has `club_id` null and `is_public_template` true.
--
-- Privacy: a public template carries only plan-design fields (name, goal,
-- weeks, workouts). The publisher's private fitness numbers
-- (vdot / current_5k_seconds) are stripped on publish AND on clone (mirrors
-- 20260721_001). No runs, PII, or notes-with-PII leak — only the columns
-- the SELECT policy below exposes are reachable, and the clone RPC copies
-- the same design-only subset clone_plan_template does.

-- ─────────────────────── Column ───────────────────────

alter table training_plans
  add column is_public_template boolean not null default false;

-- A public template must also be a template: this lets the public flag
-- inherit the active-status guard (training_plans_template_status) and the
-- weeks/workouts template-visibility chain without a parallel set of rules.
alter table training_plans
  add constraint training_plans_public_requires_template
  check (is_public_template = false or is_template = true);

-- Browse index: the library lists public templates newest-first.
create index training_plans_public_library
  on training_plans (created_at desc)
  where is_public_template = true;

-- ─────────────────────── RLS — additive SELECT policies ───────────────────────
-- Postgres OR-combines permissive policies of the same command, so these
-- new SELECT-only policies widen read access for public templates without
-- touching the owner / club / coach policies. Gated on authenticated (the
-- library is a signed-in surface, mirroring the user_profiles public-read
-- policy) so a public template is previewable + cloneable by anyone, while
-- non-public plans stay private.

create policy "anyone reads public plan templates"
  on training_plans for select
  using (is_public_template = true and auth.role() = 'authenticated');

create policy "anyone reads public template weeks"
  on plan_weeks for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and p.is_public_template = true
    )
  );

create policy "anyone reads public template workouts"
  on plan_workouts for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and p.is_public_template = true
    )
  );

-- ─────────────────────── clone_public_plan RPC ───────────────────────
-- Mirrors clone_plan_template but authorises on public visibility instead
-- of club membership: any authenticated caller may clone any
-- is_public_template row. SECURITY DEFINER so the inserts into the caller's
-- owned tables don't re-evaluate RLS per row; the explicit
-- is_public_template gate below is the single access check. Carries the
-- same rate limit, auto-complete-active-plan, and fitness-strip behaviour
-- as clone_plan_template.

create or replace function clone_public_plan(
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
    status, notes, parent_template_id, is_template, is_public_template
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false, false
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

grant execute on function clone_public_plan(uuid, date) to authenticated;
