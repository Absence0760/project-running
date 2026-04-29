-- Plan templates (decisions.md § 35).
--
-- Same shape as club-owned routes (§30): a single is_template flag
-- on training_plans, optional club_id for club ownership, and a
-- parent_template_id self-FK so cloned instances know their source.
-- The clone_plan_template RPC duplicates a template + its weeks +
-- its workouts into a user-owned instance anchored at a chosen
-- start_date. Clone-not-subscribe — athletes don't see live edits
-- from the template authoring row.

-- ─────────────────────── Columns ───────────────────────

alter table training_plans
  add column is_template boolean not null default false,
  add column parent_template_id uuid references training_plans(id) on delete set null,
  add column club_id uuid references clubs(id) on delete cascade;

create index training_plans_template_club
  on training_plans (club_id, created_at desc)
  where is_template = true;

create index training_plans_parent_template
  on training_plans (parent_template_id)
  where parent_template_id is not null;

-- Templates are authoring artifacts; they shouldn't claim the per-user
-- "active plan" slot. The existing partial unique index already filters
-- on `status = 'active'`, so a template with status <> 'active' won't
-- conflict — but make it impossible to *set* status='active' on a
-- template by accident.
alter table training_plans
  add constraint training_plans_template_status
  check (is_template = false or status <> 'active');

-- ─────────────────────── RLS additions ───────────────────────
-- The existing self-only policy `"users own their plans"` (for all using
-- auth.uid() = user_id) stays in place. Two new SELECT-only policies
-- layer on top so club templates are readable by club members; a third
-- ALL policy lets club admins write club templates.

create policy "club members read club templates"
  on training_plans for select
  using (
    is_template = true
    and club_id is not null
    and is_club_member(club_id)
  );

create policy "club admins write club templates"
  on training_plans for all
  using (
    is_template = true
    and club_id is not null
    and is_club_admin(club_id)
  );

-- The plan_weeks + plan_workouts policies originally used
-- `user_id = auth.uid()` inside the EXISTS subquery, which blocks
-- club-template visibility for non-owners. Relax to a plain EXISTS:
-- the subquery against training_plans now respects training_plans'
-- own RLS (own plans + club templates), so transitivity holds.

drop policy if exists "users own their plan weeks" on plan_weeks;
create policy "users own their plan weeks"
  on plan_weeks for all
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
    )
  );

drop policy if exists "users own their plan workouts" on plan_workouts;
create policy "users own their plan workouts"
  on plan_workouts for all
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
    )
  );

-- ─────────────────────── clone_plan_template RPC ───────────────────────
-- Duplicates a template into a user-owned instance, anchored at a
-- chosen start_date. The function is SECURITY DEFINER so it can write
-- into the caller's owned tables without each operation re-evaluating
-- RLS, but we manually verify the caller can SELECT the template
-- (RLS-equivalent gate) before doing anything.

create or replace function clone_plan_template(
  template_id uuid,
  new_start_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  date_offset_days int;
  new_plan_id uuid;
  week_record record;
  workout_record record;
  new_week_id uuid;
begin
  if caller is null then
    raise exception 'clone_plan_template: not authenticated';
  end if;

  -- Read the template using the *caller's* RLS view: a non-member of
  -- the owning club won't get a row back. We re-enable RLS for the
  -- check by looking through a view-equivalent — the EXISTS test runs
  -- with security definer disabled for that statement. Easier: do a
  -- plain SELECT and let the caller_id check on results catch the
  -- gap.
  select * into tmpl from training_plans
    where id = template_id and is_template = true;

  if not found then
    raise exception 'clone_plan_template: template % not found', template_id;
  end if;

  -- Authorisation: the caller must be able to SELECT the template
  -- under normal RLS. Re-evaluate by checking explicit conditions.
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
    tmpl.days_per_week, tmpl.vdot, tmpl.current_5k_seconds,
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

grant execute on function clone_plan_template(uuid, date) to authenticated;
