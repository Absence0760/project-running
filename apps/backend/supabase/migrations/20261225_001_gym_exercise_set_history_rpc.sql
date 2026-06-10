-- One exercise's set history, normalised-name matched, server-side.
--
-- /gym/exercise?name=X renders a single exercise's progression over time. It
-- called fetchGymSetHistory() — the user's ENTIRE gym_sets history — then
-- filtered to the one exercise in JS via exercise_history.ts#exerciseProgress
-- (which groups by the normalised name: trim → lowercase → collapse internal
-- whitespace). That ships every set just to keep a handful (perf-hunt follow-up
-- 2026-06-10).
--
-- This RPC returns only the sets whose exercise name normalises to the same
-- key as p_name, so the read is bounded to that one exercise. The normalisation
-- expression matches normaliseExerciseName in gym_prs.ts exactly, so the server
-- filter selects the same sessions the client used to group together (an exact
-- `=` filter would miss a session logged under a different capitalisation /
-- spacing). SECURITY INVOKER → gym_sets / gym_workouts owner-only RLS scopes it
-- to the caller, plus an explicit auth.uid() filter.

create or replace function gym_exercise_set_history(p_name text)
returns table (
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric
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
    s.rpe
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g')
      = regexp_replace(lower(btrim(p_name)), '\s+', ' ', 'g');
$$;

revoke execute on function gym_exercise_set_history(text) from public;
grant  execute on function gym_exercise_set_history(text) to authenticated;
