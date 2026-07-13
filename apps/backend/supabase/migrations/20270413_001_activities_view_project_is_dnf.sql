-- Project `is_dnf` into the `activities` view's runs-branch summary so the
-- client twin `challenge_progress.ts` / `.dart` (`metricFromActivity`) can
-- exclude DNF'd runs from an offline-optimistic challenge-progress estimate —
-- matching the server-side exclusion migration `20270407_001` added to
-- `challenge_leaderboard` / `recompute_challenge_completion` (ADR 231). Without
-- this the view carried no `is_dnf`, so a just-DNF'd run's distance still
-- counted toward a client-side "run 100 km this month" estimate until the next
-- authoritative server re-fetch.
--
-- CREATE OR REPLACE stays legal: the view's output columns
-- (id, user_id, kind, started_at, summary, is_public) and their types are
-- unchanged — only the jsonb `summary` builder on the runs branch grows one
-- key. `runs.is_dnf` is NOT NULL default false (migration
-- 20261207_001_promote_activity_type_is_dnf), so the key always emits a real
-- true/false. security_invoker
-- and the authenticated grant are preserved verbatim.
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
    'activity_type', r.activity_type,
    'elevation_gain_m', r.elevation_gain_m,
    'is_dnf', r.is_dnf
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
