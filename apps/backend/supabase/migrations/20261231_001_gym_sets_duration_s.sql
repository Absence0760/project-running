-- gym_sets.duration_s — make timed work (planks, holds, intervals) first-class.
--
-- Mirrors gym_workouts.duration_s (20261204_001): a nullable, non-negative
-- seconds column. Optional on every set — a set may carry reps, weight, a hold
-- time, or any combination. Unblocks logging a 90s plank without abusing
-- reps/notes, and is the column session_planner.md open Q1 settled on for
-- landing a timed hold in gym_sets (instructor_business.md M2).

alter table public.gym_sets
  add column duration_s integer check (duration_s is null or duration_s >= 0);

comment on column public.gym_sets.duration_s is
  'Optional hold/interval time in seconds for timed work (planks, holds); null for rep/load-only sets.';

-- Surface the new column on the per-exercise set-history RPC
-- (20261225_001) so the progression view can read a set's hold time. Adding a
-- column to RETURNS TABLE changes the return type, which CREATE OR REPLACE
-- refuses (42P13) — drop then recreate. Full body re-emitted: keep the
-- normalisation expression + auth filter + grants identical to the prior
-- migration; only duration_s is added to RETURNS TABLE + SELECT.
drop function if exists gym_exercise_set_history(text);

create function gym_exercise_set_history(p_name text)
returns table (
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric,
  duration_s integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    s.workout_id,
    gw.started_at,
    s.exercise_name,
    s.reps,
    s.weight_kg,
    s.rpe,
    s.duration_s
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g')
      = regexp_replace(lower(btrim(p_name)), '\s+', ' ', 'g');
$$;

revoke execute on function gym_exercise_set_history(text) from public;
grant  execute on function gym_exercise_set_history(text) to authenticated;
