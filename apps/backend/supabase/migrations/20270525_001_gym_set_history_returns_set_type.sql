-- Surface gym_sets.set_type (20270228_001) on both set-history RPCs.
--
-- The prescriber (gym_progression.ts ↔ gym_progression.dart) drops a warmup by
-- reading exactly that column, and its callers on web are fed by these two
-- RPCs — neither of which returned it. Unlabelled, every ramp-up arrived
-- looking like a working set. `workingSets` (decisions § 602) narrows the
-- judgement to the session's top completed weight, which drops a LIGHTER
-- ramp-up label or no label; what it cannot catch is an explicitly-typed
-- warmup logged AT the working weight. Mobile reads its local store, which
-- carries the column, so it excluded that set and web did not — a divergence
-- in a prescriber that decides what load a lifter is told to put on the bar.
--
-- Additive: a new trailing column on each return table. Existing callers
-- select by name and are unaffected.
--
-- Adding a column to RETURNS TABLE changes the return type, which CREATE OR
-- REPLACE refuses (42P13) — drop then recreate, the same shape 20261231_001
-- used to land duration_s on the singular RPC. Both bodies are re-emitted
-- verbatim apart from the new column, and the grants are re-issued: DROP
-- FUNCTION takes the privileges with it, so an unre-issued grant leaves the
-- RPC callable by nobody.
--
-- Lock impact (migration_locks.md): no table is touched. DROP/CREATE FUNCTION
-- locks the pg_proc entry only, and the migration's own transaction makes the
-- swap atomic for concurrent callers.

drop function if exists gym_exercise_set_history(text);

create function gym_exercise_set_history(p_name text)
returns table (
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric,
  duration_s integer,
  set_type text
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
    s.duration_s,
    s.set_type
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g')
      = regexp_replace(lower(btrim(p_name)), '\s+', ' ', 'g');
$$;

revoke execute on function gym_exercise_set_history(text) from public;
grant  execute on function gym_exercise_set_history(text) to authenticated;

drop function if exists gym_exercise_set_history_batch(text[]);

create function gym_exercise_set_history_batch(p_names text[])
returns table (
  normalised_name text,
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric,
  duration_s integer,
  set_type text
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
    s.duration_s,
    s.set_type
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
