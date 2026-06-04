-- F8 (audit-db-optimization): normalize the activity timestamp name.
--
-- runs.started_at, gym_workouts.started_at, food_log.logged_at — three
-- modality tables, two names for "when the thing happened." The
-- `activities` view papered over it with `f.logged_at as started_at`.
-- Rename food_log.logged_at -> started_at so all three agree and the
-- view alias disappears.
--
-- A plain RENAME COLUMN preserves the data and auto-updates the
-- food_log_user index (it tracks the column by number, not name). The
-- Dart generator's _parseAlterTable now understands `rename column`
-- (see scripts/gen_dart_models.dart) so db_rows.dart's FoodLogRow picks
-- up `started_at`.
--
-- updated_at vs last_modified_at: SETTLED as a documented two-clock
-- convention, not a rename (see docs/architecture/conventions.md
-- "Timestamp columns" + docs/backend/api_database.md). last_modified_at
-- is the client-stamped sync clock on the offline-first tables
-- (gym_workouts, food_log, gear) — deliberately no server trigger so it
-- can't clobber the client's newer-wins reconciliation timestamp.
-- updated_at is the server clock on runs. The two names mean opposite
-- things by design; renaming runs.updated_at would churn ~50 client
-- sites for no behavioural gain, so the decision is to keep both names
-- and document the split.

alter table public.food_log rename column logged_at to started_at;

-- Recreate the activities view so the meal branch reads f.started_at
-- directly (the `logged_at as started_at` alias is gone). Output column
-- names/types/order are unchanged, so CREATE OR REPLACE is legal.
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
  f.started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary
from public.food_log f;

grant select on public.activities to authenticated;
