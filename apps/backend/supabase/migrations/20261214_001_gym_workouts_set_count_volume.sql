-- F7: retire the two correlated subqueries the `activities` view runs per gym
-- row.
--
-- The view's lift branch ran `(select count(*) ...)` and `(select sum(reps *
-- weight_kg) ...)` over gym_sets for every workout in the UNION. For a
-- power-lifter with hundreds of sessions a "last 30 activities" read fans out
-- to dozens of correlated subqueries. multi_modal.md already named the
-- mitigation: stored set_count / volume_kg columns on gym_workouts maintained
-- by a trigger. This lands it now so the History timeline reads a flat column.
--
-- The columns are trigger-maintained derived state (see derived_state.md): the
-- authoritative recompute is the same count/sum over gym_sets the view used to
-- run inline. The trigger recomputes the affected workout('s) totals from
-- scratch on every gym_sets insert/update/delete (rather than incrementing) so
-- a partial-update bug can't accumulate drift — a full recompute over one
-- workout's sets is cheap.

alter table public.gym_workouts
  add column set_count integer not null default 0;
alter table public.gym_workouts
  add column volume_kg numeric not null default 0;

-- Backfill from existing sets (the table is pre-launch / empty in prod, but
-- keep the migration correct for any local seed data).
update public.gym_workouts w
  set set_count = coalesce(agg.cnt, 0),
      volume_kg = coalesce(agg.vol, 0)
  from (
    select workout_id,
           count(*) as cnt,
           sum(coalesce(reps, 0) * coalesce(weight_kg, 0)) as vol
    from public.gym_sets
    group by workout_id
  ) agg
  where agg.workout_id = w.id;

create or replace function refresh_gym_workout_totals(p_workout_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.gym_workouts w
    set set_count = coalesce(agg.cnt, 0),
        volume_kg = coalesce(agg.vol, 0)
    from (
      select count(*) as cnt,
             sum(coalesce(reps, 0) * coalesce(weight_kg, 0)) as vol
      from public.gym_sets
      where workout_id = p_workout_id
    ) agg
    where w.id = p_workout_id;
end;
$$;

create or replace function gym_sets_maintain_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_gym_workout_totals(OLD.workout_id);
    return OLD;
  end if;
  -- INSERT or UPDATE: refresh NEW's workout, and OLD's too if a set moved
  -- between workouts.
  perform refresh_gym_workout_totals(NEW.workout_id);
  if tg_op = 'UPDATE' and OLD.workout_id is distinct from NEW.workout_id then
    perform refresh_gym_workout_totals(OLD.workout_id);
  end if;
  return NEW;
end;
$$;

create trigger gym_sets_maintain_totals_trigger
  after insert or update or delete on public.gym_sets
  for each row execute function gym_sets_maintain_totals();

-- ─────────── activities view: read the columns, not the subqueries ───────────
-- Full body re-emitted (latest is 20261209_001). Only the lift branch's
-- summary changes: set_count / volume_kg now read w.set_count / w.volume_kg.
-- Output columns + types + order are unchanged, so CREATE OR REPLACE is legal.
create or replace view public.activities
with (security_invoker = true) as
select
  r.id,
  r.user_id,
  'run'::text as kind,
  r.started_at,
  jsonb_build_object(
    'distance_m', r.distance_m,
    'duration_s', r.duration_s,
    'activity_type', r.activity_type
  ) as summary,
  r.is_public
from public.runs r
union all
select
  w.id,
  w.user_id,
  'lift'::text as kind,
  w.started_at,
  jsonb_build_object(
    'title', w.title,
    'set_count', w.set_count,
    'volume_kg', w.volume_kg
  ) as summary,
  w.is_public
from public.gym_workouts w
union all
select
  f.id,
  f.user_id,
  'meal'::text as kind,
  f.started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary,
  f.is_public
from public.food_log f;

grant select on public.activities to authenticated;
