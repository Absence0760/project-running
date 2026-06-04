-- F1 (audit-db-optimization, decision D1): drop the vestigial `runs.kind`.
--
-- 20261204_001 added `runs.kind text not null default 'run' check (kind in
-- ('run','lift','meal'))` as a "future merge is a column change, not a
-- re-model" placeholder. But `runs` only ever holds 'run' — the column is
-- dead weight that makes the schema *look* polymorphic when it isn't. The
-- three modalities live in their own tables (`runs`, `gym_workouts`,
-- `food_log`) and the `activities` view is the read-time unifier. So `runs`
-- is honestly a running table; drop `kind`.
--
-- The `activities` view's runs branch selected `r.kind` directly (the
-- lift/meal branches already project literals). Recreate the view first so
-- the runs branch projects the literal `'run'::text` too, THEN drop the
-- column. Output column names/types/order are unchanged, so CREATE OR
-- REPLACE is legal (no 42P16).
--
-- Client plumbing dropped alongside this migration: the `runs.kind` /
-- `ActivityKind` pair in apps/web/scripts/check_constraint_unions.mjs and the
-- `ActivityKind` union + `Run.kind` field in apps/web/src/lib/types.ts. No
-- web or Dart code reads `run.kind` (the `activities` view consumer uses its
-- own inline `kind` union); the column was referenced only by the type layer.

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
    'activity_type', r.metadata ->> 'activity_type'
  ) as summary
from public.runs r
union all
select
  w.id,
  w.user_id,
  'lift'::text as kind,
  w.started_at,
  jsonb_build_object(
    'title', w.title,
    'set_count', (select count(*) from public.gym_sets s where s.workout_id = w.id),
    'volume_kg', (
      select coalesce(sum(coalesce(s.reps, 0) * coalesce(s.weight_kg, 0)), 0)
      from public.gym_sets s where s.workout_id = w.id
    )
  ) as summary
from public.gym_workouts w
union all
select
  f.id,
  f.user_id,
  'meal'::text as kind,
  f.logged_at as started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary
from public.food_log f;

grant select on public.activities to authenticated;

alter table public.runs drop column kind;
