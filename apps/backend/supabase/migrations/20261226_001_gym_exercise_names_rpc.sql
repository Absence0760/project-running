-- Distinct logged exercise names (most-used first), for editor autocomplete.
--
-- The History page lazily pulled the user's ENTIRE gym_sets history just to
-- derive the distinct exercise names that feed the gym editor's datalist
-- (ensureGymSuggestions). That ships thousands of set rows to extract a few
-- dozen names (perf-hunt follow-up 2026-06-10).
--
-- This RPC returns one row per distinct trimmed name + its use count, ordered
-- most-used first — the same shape the client built in JS. Bounded to the
-- number of distinct exercises the user has logged (dozens), not their set
-- count. SECURITY INVOKER → gym_sets / gym_workouts owner-only RLS scopes it to
-- the caller, plus an explicit auth.uid() filter. Names stay case-preserved
-- (trim only), matching the prior datalist behaviour where "Bench Press" and
-- "bench press" were distinct suggestions.

create or replace function gym_exercise_names()
returns table (
  exercise_name text,
  uses integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    btrim(s.exercise_name) as exercise_name,
    count(*)::int as uses
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and btrim(coalesce(s.exercise_name, '')) <> ''
  group by btrim(s.exercise_name)
  order by count(*) desc, btrim(s.exercise_name);
$$;

revoke execute on function gym_exercise_names() from public;
grant  execute on function gym_exercise_names() to authenticated;
