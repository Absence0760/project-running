-- Project `duration_s` into the `activities` view's lift-branch summary.
--
-- `gym_workouts.duration_s` has existed since the Phase 4 foundation
-- (20261204_001) but the view never carried it, so every consumer reading a
-- strength session through `activities` saw a null duration. The mobile
-- nutrition surface derives its dynamic-TDEE exercise calories and its
-- hydration exercise-minutes from exactly that field, so a logged gym session
-- contributed zero on both counts — the runs branch has always projected
-- `duration_s`, and the lift branch is the odd one out.
--
-- CREATE OR REPLACE stays legal: the view's output columns
-- (id, user_id, kind, started_at, summary, is_public) and their types are
-- unchanged — only the jsonb `summary` builder on the lift branch grows one
-- key. `duration_s` is nullable on the table (a set-logged session with no
-- timer has none), so consumers must keep treating a null as "unknown", not
-- zero. security_invoker and the authenticated grant are preserved verbatim.
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
    'volume_kg', w.volume_kg,
    'duration_s', w.duration_s
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
