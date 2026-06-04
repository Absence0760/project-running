-- MM1 (Round 5, audit-db-optimization): harden the `activities` view as the
-- documented cross-modality contract.
--
-- The `activities` UNION view (20261204_001) is the single read-time unifier
-- for the multi-modal History timeline and — per multi_modal.md § "Social
-- feed" — the path the social feed will reuse to surface public lift cards
-- alongside runs. It projected (id, user_id, kind, started_at, summary), but
-- NOT is_public. Without it the feed path can't filter `where is_public` over
-- the view: it would have to fall back to RLS visibility (which scopes to the
-- caller, not "public to everyone") or re-query each base table, defeating the
-- one-query contract. All three base tables already carry is_public
-- (runs / gym_workouts / food_log), so the view can project it uniformly.
--
-- Appended at the END of the select list so CREATE OR REPLACE stays legal
-- (Postgres permits adding columns to the tail of a view's output, but not
-- reordering / retyping existing ones). The runs branch keeps projecting the
-- literal 'run' kind and the real activity_type column (20261206_001 /
-- 20261207_001); the meal branch reads food_log.started_at directly
-- (20261208_001). security_invoker = true is preserved so the base tables' RLS
-- still applies to the querying user.

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
    'set_count', (select count(*) from public.gym_sets s where s.workout_id = w.id),
    'volume_kg', (
      select coalesce(sum(coalesce(s.reps, 0) * coalesce(s.weight_kg, 0)), 0)
      from public.gym_sets s where s.workout_id = w.id
    )
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
