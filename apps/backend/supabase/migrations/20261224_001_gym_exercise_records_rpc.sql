-- Per-exercise all-time strength records, aggregated server-side.
--
-- /gym/records used to call fetchGymSetHistory() — which ships EVERY gym_sets
-- row the user has ever logged to the browser (a 3-year lifter ≈ 15k rows, no
-- bound) — and recompute the per-exercise bests in JS via exerciseRecords()/
-- gym_prs.ts. Records are all-time maxima, so a windowed client read can't
-- serve them; the durable fix is to aggregate on the server and return one row
-- per exercise (perf-hunt follow-up, 2026-06-10).
--
-- This RPC is the SQL mirror of exercise_records.ts#exerciseRecords +
-- gym_prs.ts#computeExercisePrs. It is recompute-on-read (no stored cache, so
-- it can't drift from gym_sets) and SECURITY INVOKER, so the gym_workouts /
-- gym_sets owner-only RLS scopes it to the caller — plus an explicit
-- auth.uid() filter for clarity. The metrics MUST stay in lockstep with the
-- TS engine; segment_effort_ranks-style pgTAP (gym_exercise_records_test.sql)
-- pins the math against the same fixtures gym_prs.test.ts uses.
--
-- Per-exercise metrics (keyed by the normalised name = trim → lowercase →
-- collapse internal whitespace, matching normaliseExerciseName):
--   heaviest_weight_kg   max weight_kg over weighted sets
--   heaviest_weight_reps reps at that heaviest weight (ties → most reps)
--   best_volume_kg       max(reps · weight_kg), rounded 1dp
--   best_est_1rm_kg      max Epley e1rm, rounded 1dp; a true single (reps=1)
--                        reports the lifted weight, else w·(1 + min(reps,12)/30)
--   last_performed_at    most recent workout.started_at including the exercise
--   session_count        distinct workouts including the exercise
-- Bodyweight-only exercises (no positive-weight set) are excluded, exactly as
-- they're excluded from the TS weight/volume/e1rm metrics. Ordered most-
-- recently-performed first, ties broken by display name.

create or replace function gym_exercise_records()
returns table (
  exercise_name text,
  heaviest_weight_kg numeric,
  heaviest_weight_reps integer,
  best_volume_kg numeric,
  best_est_1rm_kg numeric,
  last_performed_at timestamptz,
  session_count integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with norm as (
    select
      regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') as key,
      s.exercise_name as display,
      s.reps,
      s.weight_kg,
      s.workout_id,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and btrim(coalesce(s.exercise_name, '')) <> ''
  ),
  meta as (
    select
      key,
      max(started_at) as last_performed_at,
      count(distinct workout_id)::int as session_count,
      (array_agg(display order by started_at desc, display))[1] as display
    from norm
    group by key
  ),
  weighted as (
    select key, reps, weight_kg
    from norm
    where weight_kg is not null and weight_kg > 0
  ),
  bests as (
    select
      key,
      max(weight_kg) as heaviest_weight_kg,
      round(max(case when reps is not null and reps > 0 then weight_kg * reps end), 1)
        as best_volume_kg,
      round(max(case when reps is not null and reps > 0
                     then case when reps = 1 then weight_kg
                               else weight_kg * (1 + least(reps, 12)::numeric / 30) end
                end), 1) as best_est_1rm_kg
    from weighted
    group by key
  ),
  heaviest_reps as (
    select distinct on (key) key, reps as heaviest_weight_reps
    from weighted
    order by key, weight_kg desc, reps desc nulls last
  )
  select
    m.display as exercise_name,
    b.heaviest_weight_kg,
    hr.heaviest_weight_reps,
    b.best_volume_kg,
    b.best_est_1rm_kg,
    m.last_performed_at,
    m.session_count
  from meta m
  join bests b on b.key = m.key
  join heaviest_reps hr on hr.key = m.key
  order by m.last_performed_at desc, m.display;
$$;

revoke execute on function gym_exercise_records() from public;
grant  execute on function gym_exercise_records() to authenticated;
