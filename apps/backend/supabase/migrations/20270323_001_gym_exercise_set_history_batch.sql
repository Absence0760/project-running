-- Batched sibling of gym_exercise_set_history (20261225_001 / 20261231_001):
-- the web gym session + detail pages called the singular RPC once per
-- exercise (an N+1 of round-trips per rendered workout). A client-side
-- PostgREST `.in('exercise_name', ...)` batch would be WRONG — the name match
-- must be on the normalised key (trim → lowercase → collapse whitespace,
-- matching normaliseExerciseName in gym_prs.ts), or differently-capitalised /
-- spaced logged sets silently drop out of the history.
--
-- Same row shape as the singular RPC plus `normalised_name`, so one call
-- serves N exercises and the client groups per input name by the same key it
-- already computes. Same posture: SECURITY INVOKER (gym_sets / gym_workouts
-- owner-only RLS) plus the explicit auth.uid() filter.

create or replace function gym_exercise_set_history_batch(p_names text[])
returns table (
  normalised_name text,
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
    regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') as normalised_name,
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
    and regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') in (
      select regexp_replace(lower(btrim(n)), '\s+', ' ', 'g')
      from unnest(coalesce(p_names, '{}'::text[])) as n
      where btrim(coalesce(n, '')) <> ''
    );
$$;

revoke execute on function gym_exercise_set_history_batch(text[]) from public;
grant  execute on function gym_exercise_set_history_batch(text[]) to authenticated;
